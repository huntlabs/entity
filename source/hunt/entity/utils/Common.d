
module hunt.entity.utils.Common;

import std.traits;
import hunt.entity.Entity;
import hunt.entity.Constant;

import std.format;

class Common {
    static T sampleCopy(T)(T t) {
        T copy = new T();
        foreach(memberName; __traits(derivedMembers, T)) {
            static if (__traits(getProtection, __traits(getMember, T, memberName)) == "public")  {
                alias memType = typeof(__traits(getMember, T ,memberName));
                static if (!isFunction!(memType)) {
                    mixin("copy."~memberName~" = "~"t."~memberName~";\n");
                }
            }
        }
        foreach(key, value; t.getAllLazyData()) {
            copy.addLazyData(key, new LazyData(value));
        }
        copy.setManager(t.getManager());
        return copy;
    }

    static bool inArray(T)(T[] ts, T t) {
        foreach(v; ts) {
            if(v == t)
                return true;
        }
        return false;
    }

    static string quoteStr(string s) {
        if (s == "length")
            return s;
        return "\""~s~"\"";
    }

}

/// returns table name for class type
string getTableName(T : Object)() {
    string name = T.stringof;
    foreach (a; __traits(getAttributes, T)) {
        static if (is(typeof(a) == Table)) {
            name = a.name;
            break;
        }
    }
    return name;
}

string getJoinTableName(T, string m)() {
    string name = null;
    {
        foreach(a; __traits(getAttributes, __traits(getMember,T,m))) {
            static if (is(typeof(a) == JoinTable)) {
                name = (a.name);
                break;
            }
        }
    }
    return name;
}

string getPrimaryKey(T : Object)() {
    string name = "id";
    foreach (m; __traits(allMembers, T)) {
        static if (__traits(compiles, (typeof(__traits(getMember, T, m))))){
            alias memType = typeof(__traits(getMember, T ,m));
            static if (!isFunction!(memType) && hasUDA!(__traits(getMember, T ,m), PrimaryKey)) {
                name = m;
            }
        }
    }
      
    return name;
}

JoinColumn getJoinColumn(T, string m)() {
    JoinColumn joinColum ;
    {
        foreach(a; __traits(getAttributes, __traits(getMember,T,m))) {
            static if (is(typeof(a) == JoinColumn)) {
                joinColum = a;
                break;
            }
        }
    }
    return joinColum;
}

InverseJoinColumn getInverseJoinColumn(T, string m)() {
    InverseJoinColumn joinColum ;
    {
        foreach(a; __traits(getAttributes, __traits(getMember,T,m))) {
            static if (is(typeof(a) == InverseJoinColumn)) {
                joinColum = a;
                break;
            }
        }
    }
    return joinColum;
}

unittest{
    import hunt.entity;
    import hunt.logging;

    @Table("UserInfo")
    class UserInfo  {

        @AutoIncrement @PrimaryKey 
        int id;


        @Column("nickname")
        string nickName;
        int age;


    }

    @Table("AppSInfo")
    class AppInfo  {

        @AutoIncrement @PrimaryKey 
        int id;

        string name;
        string desc;
        
        @JoinTable("UserApp")
        @JoinColumn("appid","id")
        @InverseJoinColumn("uid","id")
        @ManyToMany("apps")
        UserInfo[] uinfos;
    }

    logDebug("Table Name : %s ".format(getTableName!AppInfo));
    logDebug("Join Table Name : %s ".format(getJoinTableName!(AppInfo,"uinfos")));
    logDebug("Join  Column : %s ".format(getJoinColumn!(AppInfo,"uinfos")));
    logDebug("Inverse Join  Column : %s ".format(getInverseJoinColumn!(AppInfo,"uinfos")));
    logDebug("PrimaryKey : %s ".format(getPrimaryKey!AppInfo));

}


private enum string IndentString = "                                ";  // 32 spaces

string indent(size_t number) {
    assert(number>0 && IndentString.length, "Out of range");
    return IndentString[0..number];
}
