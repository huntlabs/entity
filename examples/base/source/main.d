
import std.algorithm;
import std.stdio;

import entity;

// Annotations of entity classes
class User
{
    long id;
    string name;
    Customer customer;
    @ManyToMany // cannot be inferred, requires annotation
    LazyCollection!Role roles;
}

class Customer
{
    int id;
    string name;
    // Embedded is inferred from type of Address
    Address address;
    
    Lazy!AccountType accountType; // ManyToOne inferred
    
    User[] users; // OneToMany inferred
    
    this()
    {
        address = new Address();
    }
}

@Embeddable
class Address
{
    string zip;
    string city;
    string streetAddress;
}

class AccountType
{
    int id;
    string name;
}

class Role
{
    int id;
    string name;
    @ManyToMany // w/o this annotation will be OneToMany by convention
    LazyCollection!User users;
}

int main()
{
    // create metadata from annotations
    EntityMetaData schema = new SchemaInfoImpl!(User, Customer, AccountType, Address, Role);
    
    // setup DB connection factory
    version (USE_MYSQL)
    {
        MySQLDriver driver = new MySQLDriver();
        string url = MySQLDriver.generateUrl("localhost", 3306, "test_db");
        import std.stdio;
        writeln("url:", url);
        string[string] params = MySQLDriver.setUserAndPassword("testuser", "testpasswd");
        Dialect dialect = new MySQLDialect();
    } else {
        SQLITEDriver driver = new SQLITEDriver();
        string url = "zzz.db"; // file with DB
        static import std.file;
       
        string[string] params;
        Dialect dialect = new SQLiteDialect();
    }
        
    DataSource ds = new ConnectionPoolDataSourceImpl(driver, url, params);
    

    // create managerion factory
    EntityManagerFactory factory = new EntityManagerFactory(schema, dialect, ds);
    scope(exit) factory.close();

    // Create schema if necessary
    {
        // get connection
        Connection conn = ds.getConnection();
        scope(exit) conn.close();
        // create tables if not exist
        factory.getDBMetaData().updateDBSchema(conn, false, true);
    }

    // Now you can use HibernateD

    // create managerion
    EntityManager manager = factory.createEntityManager();
    scope(exit) manager.close();

    // use managerion to access DB

    // read all users using query
    Query q = manager.createQuery("FROM User ORDER BY name");
    User[] list = q.list!User();

    // create sample data
    Role r10 = new Role();
	
    r10.name = "role10";
    Role r11 = new Role();
	
    r11.name = "role11";
    Customer c10 = new Customer();
	
    c10.name = "Customer 10";
	
    c10.address = new Address();
	
    c10.address.zip = "12345";
    c10.address.city = "New York";
    c10.address.streetAddress = "Baker st., 12";
	
    User u10 = new User();
    u10.name = "Alex";
    u10.customer = c10;
    u10.roles = [r10, r11];
	
    manager.persist(r10);
    manager.persist(r11);
    manager.persist(c10);
    manager.persist(u10);
	
    manager.close();
	
    manager = factory.createEntityManager();

    // load and check data
    User u11 = manager.createQuery("FROM User WHERE name=:Name").setParameter("Name", "Alex").uniqueResult!User();

    writeln("u11.customer.users.length=", u11.customer.users.length);
    writeln("u11.name,", u11.name);
    writeln("u11.id,", u11.id);

    //manager.update(u11);

    // remove entity
    // manager.remove(u11);

    User u112 = manager.createQuery("FROM User WHERE name=:Name").setParameter("Name", "Alex").uniqueResult!User();

    writeln("u11.customer.users.length=", u112.customer.users.length);
    writeln("u11.name,", u112.name);
    writeln("u11.id,", u112.id);
    
    return 0;
}