module Dhall {
  theory Syntax {
    type Expr
    
    // Constants
    Type: Expr
    Kind: Expr
    Sort: Expr

    // Variables (name, De Bruijn index)
    Var: (string, int) -> Expr

    // Functions
    Lam: (name: string, type: Expr, body: Expr) -> Expr
    Pi:  (name: string, input: Expr, output: Expr) -> Expr
    App: (func: Expr, arg: Expr) -> Expr

    // Let bindings
    Let: (name: string, type: Expr, value: Expr, body: Expr) -> Expr

    // Records
    Record: [(string, Expr)] -> Expr
    RecordLit: [(string, Expr)] -> Expr
    Field: (expr: Expr, field: string) -> Expr

    // Unions
    Union: [(string, Expr?)] -> Expr // value type is optional (can be empty alternative)
    UnionLit: (tag: string, value: Expr?, alternatives: [(string, Expr?)]) -> Expr
    Merge: (handlers: Expr, union: Expr, annotation: Expr?) -> Expr


    // Primitive Literals
    boolVal: bool -> Expr
    natVal: int -> Expr // using int but treating as Nat
    textVal: string -> Expr
    
    // Operations
    Plus: (Expr, Expr) -> Expr
    Times: (Expr, Expr) -> Expr
  }

  theory Evaluation {
    include Syntax
    
    // Substitute x with v in e
    subst: (x: string, v: Expr, e: Expr) -> Expr
    subst = (x, v, e) -> e match {
      Var(y, i) -> if (x == y) v else Var(y, i)
      
      Lam(y, t, b) -> 
        if (x == y) Lam(y, subst(x,v,t), b) 
        else Lam(y, subst(x,v,t), subst(x,v,b))
        
      Pi(y, t, b) ->
        if (x == y) Pi(y, subst(x,v,t), b)
        else Pi(y, subst(x,v,t), subst(x,v,b))
        
      App(f, a) -> App(subst(x,v,f), subst(x,v,a))
      
      Let(y, t, val_, b) ->
        if (x == y) Let(y, subst(x,v,t), subst(x,v,val_), b)
        else Let(y, subst(x,v,t), subst(x,v,val_), subst(x,v,b))

      Record(entries) -> Record(map(entries)(e -> (e.0, subst(x,v,e.1))))
      RecordLit(entries) -> RecordLit(map(entries)(e -> (e.0, subst(x,v,e.1))))
      Field(r, f) -> Field(subst(x,v,r), f)

      Union(alts) -> Union(map(alts)(a -> (a.0, if (a.1 match { Some(e) -> true _ -> false }) { val Some(e) = a.1; Some(subst(x,v,e)) } else None)))
      UnionLit(tag, valO, alts) -> {
         val newValO = if (valO match { Some(e) -> true _ -> false }) { val Some(e) = valO; Some(subst(x,v,e)) } else None
         val newAlts = map(alts)(a -> (a.0, if (a.1 match { Some(e) -> true _ -> false }) { val Some(e) = a.1; Some(subst(x,v,e)) } else None))
         UnionLit(tag, newValO, newAlts)
      }
      Merge(h, u, ann) -> Merge(subst(x,v,h), subst(x,v,u), if (ann match { Some(e) -> true _ -> false }) { val Some(e) = ann; Some(subst(x,v,e)) } else None)
        
      Plus(a, b) -> Plus(subst(x,v,a), subst(x,v,b))
      Times(a, b) -> Times(subst(x,v,a), subst(x,v,b))

      _ -> e
    }

    normalize: Expr -> Expr
    normalize = e -> e match {
      // Beta Reduction
      App(f, a) -> {
        val f_norm = normalize(f)
        val a_norm = normalize(a)
        
        if (f_norm match { Lam(x, t, b) -> true _ -> false }) {
           val Lam(x, t, b) = f_norm
           normalize(subst(x, a_norm, b))
        } else {
           App(f_norm, a_norm)
        }
      }

      // Let folding
      Let(x, t, v, b) -> {
        val v_norm = normalize(v)
        normalize(subst(x, v_norm, b))
      }
      
      // Record Projection
      Field(r, f) -> {
        val r_norm = normalize(r)
        if (r_norm match { RecordLit(_) -> true _ -> false }) {
           val RecordLit(entries) = r_norm
           // simplified lookup
           val found = fold(entries, None, (acc, entry) -> if (entry.0 == f) Some(entry.1) else acc)
           if (found match { Some(e) -> true _ -> false }) {
             val Some(e) = found
             normalize(e) 
           } else {
             Field(r_norm, f)
           }
        } else {
           Field(r_norm, f)
        }
      }

      // Merge on Union
      Merge(handlers, u, ann) -> {
        val h_norm = normalize(handlers)
        val u_norm = normalize(u)
        
        if (u_norm match { UnionLit(_,_,_) -> true _ -> false } & h_norm match { RecordLit(_) -> true _ -> false }) {
           val UnionLit(tag, valO, _) = u_norm
           val RecordLit(entries) = h_norm
           
           val handler = fold(entries, None, (acc, entry) -> if (entry.0 == tag) Some(entry.1) else acc)
           
           if (handler match { Some(h) -> true _ -> false }) {
             val Some(h) = handler
             if (valO match { Some(v) -> true _ -> false }) {
                val Some(v) = valO
                // h is a function expecting the union value
                normalize(App(h, v))
             } else {
                // h is a value (for empty alternative) ? In Dhall merge handles constructors. 
                // Actually if alt is empty, handler is just a value.
                // We need to know if the union constructor had a payload type or not. assumed yes for now or handle both.
                // For simplification: strict Dhall requires handlers to be functions if alt has type.
                normalize(h)
             }
           } else {
             Merge(h_norm, u_norm, ann)
           }
        } else {
           Merge(h_norm, u_norm, ann)
        }
      }

      // Natural/Plus
      Plus(a, b) -> {
        val a_norm = normalize(a)
        val b_norm = normalize(b)
        
        // Check if both are natVal
        // This clumsy 'if match' is because I am not sure about deep pattern matching in `if`.
        // But `basics.p` used pattern matching in `match`.
        
        if (a_norm match { natVal(_) -> true _ -> false } & b_norm match { natVal(_) -> true _ -> false }) {
           val natVal(na) = a_norm
           val natVal(nb) = b_norm
           natVal(na + nb)
        } else {
           Plus(a_norm, b_norm)
        }
      }
      
      // Natural/Times
      Times(a, b) -> {
        val a_norm = normalize(a)
        val b_norm = normalize(b)
        if (a_norm match { natVal(_) -> true _ -> false } & b_norm match { natVal(_) -> true _ -> false }) {
           val natVal(na) = a_norm
           val natVal(nb) = b_norm
           natVal(na * nb)
        } else {
           Times(a_norm, b_norm)
        }
      }

      // Congruence steps
      Lam(x, t, b) -> Lam(x, normalize(t), normalize(b))
      Pi(x, t, b) -> Pi(x, normalize(t), normalize(b))
      
      _ -> e
    }
  }

  module Test {
      include Evaluation
      
      testConstraints = {
         // Test 1: Identity function
         // (\x : Type -> x) Type  ==> Type
         val id = Lam("x", Type, Var("x", 0))
         val expr1 = App(id, Type)
         normalize(expr1) == Type &
         
         // Test 2: Plus
         // 2 + 3 ==> 5
         normalize(Plus(natVal(2), natVal(3))) == natVal(5) &
         
         // Test 3: Let
         // let x = 2 in x + 3 ==> 5
         normalize(Let("x", Type, natVal(2), Plus(Var("x", 0), natVal(3)))) == natVal(5) &

         // Test 4: Nested
         // (\x. x + 1) 4 ==> 5
         val f = Lam("x", Type, Plus(Var("x", 0), natVal(1)))
         normalize(App(f, natVal(4))) == natVal(5) &

         // Test 5: Record Projection
         // { x = 1, y = 2 }.x ==> 1
         normalize(Field(RecordLit([("x", natVal(1)), ("y", natVal(2))]), "x")) == natVal(1) &
         
         // Test 6: Union Merge
         // merge { Left = \x -> x, Right = \y -> 0 } (< Left = 5 >) ==> 5
         // Handlers
         val handlers = RecordLit([
            ("Left", Lam("x", Natural, Var("x", 0))),
            ("Right", Lam("y", Bool, natVal(0)))
         ])
         // Union Value: < Left = 5 >
         // We construct it with knowledge of other alternatives for type safety, though here just AST
         val uVal = UnionLit("Left", Some(natVal(5)), [("Left", Some(Natural)), ("Right", Some(Bool))])
         
         normalize(Merge(handlers, uVal, None)) == natVal(5)
      }
  }
}
