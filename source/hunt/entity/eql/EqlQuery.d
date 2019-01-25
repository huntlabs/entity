/*
 * Entity - Entity is an object-relational mapping tool for the D programming language. Referring to the design idea of JPA.
 *
 * Copyright (C) 2015-2018  Shanghai Putao Technology Co., Ltd
 *
 * Developer: HuntLabs.cn
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module hunt.entity.eql.EqlQuery;

import hunt.entity;
import hunt.sql;
import hunt.logging;
import hunt.collection;
import hunt.entity.eql.EqlParse;
import hunt.entity.eql.ResultDes;
import hunt.entity.eql.EqlInfo;
import std.exception;
import std.algorithm.searching;
import hunt.entity.eql.EqlCache;

import hunt.trace.Constrants;
import hunt.trace.Plugin;
import hunt.trace.Span;
import std.traits;


class EqlQuery(T...)
{

    alias ResultObj = T[0];

    private EntityManager _manager;
    private ResultDes!(ResultObj) _resultDes;

    private EqlParse _eqlParser;
    private string _eql;
    private string _countEql;
    private Pageable _pageable;
    private string[] _isExtracted;
    private long _offset = -1;
    private long _limit = -1;

    private Span _span;
    private string[string] _tags;

    this(string eql, EntityManager em)
    {
        _manager = em;
        _resultDes = new ResultDes!(ResultObj)(em);
        _eql = eql;

        parseEql();
    }

    this(string query_eql, Pageable page, EntityManager em)
    {
        _manager = em;
        _resultDes = new ResultDes!(ResultObj)(em);
        _eql = query_eql;
        _pageable = page;
        parseEql();
    }

    private void beginTrace(string name) {
        _tags.clear();
        _span = traceSpanBefore(name);
    }

    private void endTrace(string error = null) {
        if(_span !is null) {
            _tags["eql"] = _eql;
            traceSpanAfter(_span , _tags , error);
        }
    }

    private void parseEql()
    {
        beginTrace("EQL PARSE");
        scope(exit) endTrace();
        auto opt = _manager.getDatabase().getOption();
        if (opt.isMysql())
        {
            _eqlParser = new EqlParse(_eql, DBType.MYSQL.name);
        }
        else if (opt.isPgsql())
        {
            _eqlParser = new EqlParse(_eql, DBType.POSTGRESQL.name);
        }
        else if (opt.isSqlite())
        {
            _eqlParser = new EqlParse(_eql, DBType.SQLITE.name);
        }
        else
        {
            throw new Exception("not support dbtype : %s".format(opt.url().scheme));
        }

        auto parsedEql = eqlCache.get(_eql);
        if (parsedEql is null)
        {
            foreach (ObjType; T)
            {
                extractInfo!ObjType();
            }
            _eqlParser.parse();

            eqlCache.put(_eql, _eqlParser.getParsedEql());
        }
        else
        {
            logInfo("EQL Cache Hit : ", _eql);
            _eqlParser.setParsedEql(parsedEql);
        }

        // _countEql = PagerUtils.count(_eqlParser.getNativeSql, _eqlParser.getDBType());
    }

    private void extractInfo(ObjType)()
    {
        if (_isExtracted.canFind(ObjType.stringof))
            return;
        _isExtracted ~= ObjType.stringof;

        static if (isAggregateType!(ObjType) && hasUDA!(ObjType, Table))
        {
            {
                auto entInfo = new EqlInfo!(ObjType)(_manager);

                _eqlParser.putFields(entInfo.getEntityClassName(), entInfo.getFields);
                _eqlParser.putClsTbName(entInfo.getEntityClassName(), entInfo.getTableName());

                _eqlParser.putJoinCond(entInfo.getJoinConds());
                if (ObjType.stringof == ResultObj.stringof)
                {
                    _resultDes.setFields(entInfo.getFields);
                }
            }
        }
        else
        {
            // throw new Exception(" not support type : " ~ ObjType.stringof);
        }

        foreach (memberName; __traits(derivedMembers, ObjType))
        {
            static if (__traits(getProtection, __traits(getMember, ObjType, memberName)) == "public")
            {
                alias memType = typeof(__traits(getMember, ObjType, memberName));
                static if (is(memType == class))
                {
                    {
                        auto sub_en = new EqlInfo!(memType)(_manager);
                        _eqlParser.putFields(sub_en.getEntityClassName(), sub_en.getFields);
                        _eqlParser.putClsTbName(sub_en.getEntityClassName(), sub_en.getTableName());
                        _eqlParser._objType[ObjType.stringof ~ "." ~ memberName] = sub_en.getEntityClassName();

                        extractInfo!memType();
                    }
                }
                else if (isArray!memType)
                {
                }
            }
        }
    }

    public EqlQuery setParameter(R = string)(int idx, R param)
    {
        if (_eqlParser !is null)
        {
            _eqlParser.setParameter!R(idx, param);
        }
        return this;
    }

    public EqlQuery setParameter(R = string)(string idx, R param)
    {
        if (_eqlParser !is null)
        {
            _eqlParser.setParameter!R(idx, param);
        }
        return this;
    }

    public EqlQuery setMaxResults(long maxResult)
    {
        if(_pageable)
        {
            throw new Exception("This method is not supported!");
        }
        _limit = maxResult;
        return this;
    }

    public EqlQuery setFirstResult(long startPosition)
    {
        if(_pageable)
        {
            throw new Exception("This method is not supported!");
        }
        _offset = startPosition;
        return this;
    }

    public string getExecSql()
    {
        auto sql = strip(_eqlParser.getNativeSql());
        if (endsWith(sql, ";"))
            sql = sql[0 .. $ - 1];
        if(_pageable)
        {
            sql ~= " limit " ~ to!string(_pageable.getPageSize());
            auto offset = _pageable.getOffset();
            if ( offset > 0)
                sql ~= " offset " ~ to!string(offset);
        }
        else if(_limit != -1)
        {
            sql ~= " limit " ~ to!string(_limit);
            if (_offset != -1)
                sql ~= " offset " ~ to!string(_offset);
        }
        return sql;
    }

    public int exec()
    {
        auto sql = getExecSql();
        beginTrace("EqlQuery exec");
        scope(exit) {
            _tags["sql"] = sql;
            endTrace();
        }
        auto stmt = _manager.getSession().prepare();
        //TODO update 时 返回的row line count 为 0
        return stmt.execute();
    }

    public ResultObj getSingleResult()
    {        
        Object[] ret = _getResultList();
        if (ret.length == 0)
            return null;
        return cast(ResultObj)(ret[0]);
    }

    public ResultObj[] getResultList()
    {
        Object[] ret = _getResultList();
        if (ret.length == 0)
        {
            return null;
        }
        return cast(ResultObj[]) ret;
    }

    public Page!ResultObj getPageResult()
    {
        if (_pageable)
            _countEql = PagerUtils.count(_eqlParser.getNativeSql, _eqlParser.getDBType());
        else
        {
            throw new Exception("please use 'createPageQuery'");
        }

        auto res = getResultList();    
        return new Page!ResultObj(res, _pageable, count(_countEql));
    }   

    private Object[] _getResultList()
    {
        auto sql = getExecSql();
        beginTrace("EqlQuery _getResultList");
        scope(exit) {
                _tags["sql"] = sql;
                endTrace();
            }

        Object[] ret;
        long count = -1;
        auto stmt = _manager.getSession().prepare();
        auto res = stmt.query();
        Row[] rows;
        foreach (value; res)
        {
            rows ~= value;
        }

        foreach (k, v; rows)
        {

            try
            {
                Object t = _resultDes.deSerialize(rows, count, cast(int) k);
                if (t is null)
                {
                    if (count != -1)
                    {
                        ret ~= new Long(count);
                    }
                    else
                    {
                        throw new EntityException("getResultList has an null data");
                    }
                }
                ret ~= t;
            }
            catch (Exception e)
            {
                throw new EntityException(e.msg);
            }

        }
        return ret;
    }

    public ResultSet getNativeResult()
    {
        auto sql = getExecSql();
        beginTrace("EqlQuery getNativeResult");
        scope(exit) {
            _tags["sql"] = sql;
            endTrace();
        }

        auto stmt = _manager.getSession().prepare();
        return stmt.query();
    }

    private long count(string sql)
    {
        beginTrace("EqlQuery count");
        scope(exit) {
            _tags["sql"] = sql;
            endTrace();
        }
        long total = 0;
        auto stmt = _manager.getSession().prepare(sql);
        auto res = stmt.query();
        foreach (row; res)
        {
            total = to!int(row[0]);
        }
        return total;
    }
}
