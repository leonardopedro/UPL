module SerializationTest {
    type Person = { name: string, age: int }
    alice = Person { name = "Alice", age = 30 }
    
    data = (
        1, 
        "hello", 
        true, 
        [1, 2, 3], 
        alice
    )
    
    main = data
}
