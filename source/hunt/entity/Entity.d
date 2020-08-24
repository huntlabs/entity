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
 
module hunt.entity.Entity;

import hunt.entity;
import std.string;
import std.traits;

mixin template MakeModel()
{
    import hunt.serialization.Common;
    import hunt.validation;
    import hunt.logging.ConsoleLogger;
    import std.format;

    // pragma(msg, makeLazyData());

    mixin(makeLazyData);
    mixin(makeLazyLoadList!(typeof(this)));
    mixin(makeLazyLoadSingle!(typeof(this)));
    mixin(makeGetFunction!(typeof(this)));
    mixin MakeValid;
    /*  
     *   NOTE: annotation following code forbid auto create tables function when the EntityFactory construct for the reason when 
     *   the Entity model import other Entity model cause the dlang bug like "object.Error@src/rt/minfo.d(371): Cyclic dependency between 
     *   module SqlStruct.User and SqlStruct.Blog".
     *   if you want use the auto create tables function, you can open the following code and put all Entity model into one d file or 
     *   use EntityManagerFactory.createTables!(User,Blog) after EntityManagerFactory construct.
     */
    // shared static this() {
    //     addCreateTableHandle(getEntityTableName!(typeof(this)), &onCreateTableHandler!(typeof(this)));
    // }
}


string makeLazyData() {
    return `
    @Ignore
    private LazyData[string] _lazyDatas;

    @Ignore
    private EntityManager _manager;

    void setManager(EntityManager manager) {_manager = manager;}
    EntityManager getManager() {return _manager;}

    void addLazyData(string key, LazyData data) {
        if (data) {
            _lazyDatas[key] = data;
        }
    }
    LazyData[string] getAllLazyData() {
        return _lazyDatas;
    }
    LazyData getLazyData(string key ) {
        
        version(HUNT_ENTITY_DEBUG) {
            trace("lazyDatas : %s, get : %s".format(_lazyDatas, key));
            // logDebug("Datas : %s".format(_lazyDatas[key]));
        }

        auto itemPtr = key in _lazyDatas;
        
        if(itemPtr is null) {
            warningf("No data found for %s", key);
            return null;
        } else {
            return *itemPtr;
        }
    }`;
}
string makeLazyLoadList(T)() {
    return `
    private R[] lazyLoadList(R)(LazyData data , bool manyToMany = false , string mapped = "") {
        import hunt.logging;
        // logDebug("lazyLoadList ETMANAGER : ",_manager);
        auto builder = _manager.getCriteriaBuilder();
        auto criteriaQuery = builder.createQuery!(R,`~T.stringof~`);
       
        // logDebug("****LoadList( %s , %s , %s )".format(R.stringof,data.key,data.value));

        if(manyToMany)
        {
            // logDebug("lazyLoadList for :",mapped);
            auto r = criteriaQuery.manyToManyFrom(null, this,mapped);

            auto p = builder.lazyManyToManyEqual(r.get(data.key), data.value, false);
        
            auto query = _manager.createQuery(criteriaQuery.select(r).where(p));
            auto ret = query.getResultList();
            foreach(v;ret) {
                v.setManager(_manager);
            }
            return ret;
        }
        else
        {
            auto r = criteriaQuery.from(null, this);

            auto p = builder.lazyEqual(r.get(data.key), data.value, false);
        
            auto query = _manager.createQuery(criteriaQuery.select(r).where(p));
            auto ret = query.getResultList();
            foreach(v;ret) {
                v.setManager(_manager);
            }
            return ret;
        }
        
    }`;
}
string makeLazyLoadSingle(T)() {
    return `
    private R lazyLoadSingle(R)(LazyData data) {
        auto builder = _manager.getCriteriaBuilder();
        auto criteriaQuery = builder.createQuery!(R,`~T.stringof~`);
        auto r = criteriaQuery.from(null, this);
        auto p = builder.lazyEqual(r.get(data.key), data.value, false);
        auto query = _manager.createQuery(criteriaQuery.select(r).where(p));
        R ret = cast(R)(query.getSingleResult());
        ret.setManager(_manager);
        return ret;
    }`;
}
string makeGetFunction(T)() {
    string str;
    foreach(memberName; __traits(derivedMembers, T)) {
        static if (__traits(getProtection, __traits(getMember, T, memberName)) == "public") {
            alias memType = typeof(__traits(getMember, T ,memberName));
            static if (!isFunction!(memType)) {
                static if (hasUDA!(__traits(getMember, T ,memberName), OneToOne) || hasUDA!(__traits(getMember, T ,memberName), OneToMany) ||
                            hasUDA!(__traits(getMember, T ,memberName), ManyToOne) || hasUDA!(__traits(getMember, T ,memberName), ManyToMany)) {
    str ~= `
    public `~memType.stringof~` get`~capitalize(memberName)~`() {`;
                    static if (isArray!memType) {
                        string mappedBy;
                       static if(hasUDA!(__traits(getMember, T ,memberName), ManyToMany))
                       {
                           str ~= ` bool manyToMany = true ;`;
                           
                           mappedBy = "\""~getUDAs!(__traits(getMember, T ,memberName), ManyToMany)[0].mappedBy~"\"";
                       }
                       else
                       {
                           str ~= ` bool manyToMany = false ;`;
                       }

                        str ~= `
                        if (`~memberName~`.length == 0)
                            `~memberName~` = lazyLoadList!(`~memType.stringof.replace("[]","")~`)(getLazyData("`~memberName~`"),manyToMany,`~mappedBy~`);`;
                    }
                    else {
                            str ~= `
                            if (`~memberName~` is null)
                                `~memberName~` = lazyLoadSingle!(`~memType.stringof~`)(getLazyData("`~memberName~`"));`;
                    }
        str ~= `
        return `~memberName~`;
    }`;
                }
            }
        }
    }
    return str;
}  

