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
 
module hunt.entity.repository.CrudRepository;

import hunt.entity.Persistence;
import hunt.entity.DefaultEntityManagerFactory;
import hunt.entity;
import hunt.Long;
import hunt.logging.ConsoleLogger;

import std.traits;

import hunt.entity.repository.Repository;


/**
 * 
 */
class CrudRepository(T, ID) : Repository!(T, ID)
{
    protected EntityManager _manager;

    this(EntityManager manager = null) {
        if(manager is null) {
            _manager = defaultEntityManagerFactory().currentEntityManager();
        } else {
            _manager = manager;
        }
    }

    EntityManager entityManager() {
        return _manager;
    }

    EntityManager getEntityManager() {
        return _manager;
    }

    EntityManager createEntityManager()
    {
        return defaultEntityManagerFactory().currentEntityManager();
    }

    long count()
    {
        EntityManager em = _manager ? _manager : createEntityManager();
        scope(exit) {if (!_manager) em.close();}

        CriteriaBuilder builder = em.getCriteriaBuilder();
        auto criteriaQuery = builder.createQuery!T;
        Root!T root = criteriaQuery.from();
        criteriaQuery.select(builder.count(root));

        // FIXME: Needing refactor or cleanup -@zhangxueping at 2019-10-09T17:18:45+08:00
        // 
        auto result = em.createQuery(criteriaQuery).getSingleResult();
        Long r = cast(Long)result;
        if(r is null) {
            warning(typeid(result));
            return 0;
        }
        return r.longValue();

        // RowSet rs = em.createQuery(criteriaQuery).getNativeResult();
        // if(rs.size() == 0) {
        //     warning("No data returned.");
        //     return 0;
        // }

        // Row row = rs.iterator.front();
        // return row.getLong(0);
    }

    void remove(T entity)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        em.remove!T(entity);
    }

    void removeAll()
    {
        // FIXME: Needing refactor or cleanup -@zhangxueping at 2019-7-3 10:23:27
        // user "delete from T"
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        foreach (entity; findAll())
        {
            em.remove!T(entity);
        }
    }
    
    void removeAll(T[] entities)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        foreach (entity; entities)
        {
            em.remove!T(entity);
        }
    }

    void removeById(ID id)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        em.remove!T(id);
        
    }
    
    bool existsById(ID id)
    {
        T entity = this.findById(id);
        return (entity !is null);
    }

    T[] findAll()
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        CriteriaBuilder builder = em.getCriteriaBuilder();
        auto criteriaQuery = builder.createQuery!(T);
        Root!T root = criteriaQuery.from();
        TypedQuery!T typedQuery = em.createQuery(criteriaQuery.select(root));
        return typedQuery.getResultList();
    }

    T[] findAllById(ID[] ids)
    {
        T[] entities;
        foreach (id; ids)
        {
            T entity = this.findById(id);
            if (entity !is null)
                entities ~= entity;
        }
        return entities;
    }

    T findById(ID id)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        T result = em.find!T(id);
        return result;
    }

    T save(T entity)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        if (mixin(GenerateFindById!T()) is null)
        {
            em.persist(entity);
        }
        else
        {
            em.merge!T(entity);
        }
        return entity;
    }

    T[] saveAll(T[] entities)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        T[] resultList;
        foreach (entity; entities)
        {
            if (mixin(GenerateFindById!T()) is null)
            {
                resultList ~= em.persist(entity);
            }
            else
            {
                em.merge!T(entity);
                resultList ~= entity;
            }
        }
        return resultList;
    }

    T insert(T entity)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        em.persist(entity);
        return entity;
    }
    T[] insertAll(T[] entities)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        T[] resultList;
        foreach (entity; entities)
        {
            resultList ~= em.persist(entity);
        }
        return resultList;
    }

    T update(T entity)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        em.merge!T(entity);
        return entity;
    }
    
    T[] updateAll(T[] entities)
    {
        auto em = _manager ? _manager : createEntityManager;
        scope(exit) {if (!_manager) em.close();}
        T[] resultList;
        foreach (entity; entities)
        {
            em.merge!T(entity);
            resultList ~= entity;
        }
        return resultList;
    }

}

string GenerateFindById(T)()
{
    return "em.find!T(entity." ~ getSymbolsByUDA!(T, PrimaryKey)[0].stringof ~ ")";
}
