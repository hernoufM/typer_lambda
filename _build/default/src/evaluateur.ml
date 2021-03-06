open Syntax;;
 
(* Generator of variable's names *)
let fresh_var, reset_gen =
    let char_gen = ref 'a'
    and num_gen = ref 0
    in
        ((function () -> 
            let var_name = (String.make 1 !char_gen) ^
                           (if !num_gen= 0 
                           then ""
                           else (string_of_int !num_gen))
            in 
                (if !char_gen = 'z' 
                then (char_gen:='a'; num_gen:=!num_gen+1)
                else char_gen := char_of_int ((int_of_char !char_gen) + 1));
                var_name),
        (function () -> char_gen := 'a'; num_gen := 0));;     

(* Barendregt rename function. Only variables related to Abstraction are renamed *)
let barendregt lt =
    let refs_checked = ref []
    and refs_renamed = ref []
    in 
        let rec variables_globals lt var_libres =
            match lt with
                Var(name) -> 
                    if StringSet.mem name var_libres
                    then StringSet.empty
                    else StringSet.singleton name
                | Abstraction(varname,corps) -> 
                    variables_globals corps (StringSet.add varname var_libres)
                | Application(lt1, lt2) -> 
                    StringSet.union (variables_globals lt1 var_libres) (variables_globals lt2 var_libres)
                | Int _ -> var_libres
                | Add (a,b) ->
                    StringSet.union (variables_globals a var_libres) (variables_globals b var_libres)
                | Sub (a,b) ->
                    StringSet.union (variables_globals a var_libres) (variables_globals b var_libres)
                | Liste lt_l ->
                    List.fold_right variables_globals lt_l var_libres
                | Head lt_l -> (variables_globals lt_l var_libres)
                | Tail lt_l -> (variables_globals lt_l var_libres)
                | Cons (elt,lt_l) -> StringSet.union (variables_globals elt var_libres) (variables_globals lt_l var_libres)
                | IfZte (cond,conseq,alt) -> StringSet.union (StringSet.union (variables_globals cond var_libres) (variables_globals conseq var_libres)) (variables_globals alt var_libres)
                | IfEte (cond,conseq,alt) -> StringSet.union (StringSet.union (variables_globals cond var_libres) (variables_globals conseq var_libres)) (variables_globals alt var_libres)
                | Fix f -> (variables_globals f var_libres)
                | Let (varname,expr,corps) -> 
                    let vars = StringSet.union (variables_globals expr var_libres) (variables_globals corps var_libres)
                    in
                        StringSet.add varname vars
                | Ref lt_ref -> 
                    if List.mem lt_ref !refs_checked 
                    then StringSet.empty
                    else (refs_checked := lt_ref::!refs_checked; 
                          variables_globals !lt_ref var_libres)
                | Deref lt -> variables_globals lt var_libres
                | Assign (lt_ref,lt) -> StringSet.union (variables_globals lt_ref var_libres) (variables_globals lt var_libres)
                | Unit -> StringSet.empty 
        in 
            let var_globs = variables_globals lt StringSet.empty
            in
                let rec barendregt_rec lt rename =
                    match lt with
                        Var(name) -> 
                            (match StringMap.find_opt name rename with
                                None -> create_var name
                                | Some y -> create_var y)
                        | Abstraction(varname,lt) -> 
                            (let new_varname = ref (fresh_var ())
                            in
                                while StringSet.mem !new_varname var_globs do
                                    new_varname := fresh_var ()
                                done;
                                create_abs !new_varname (barendregt_rec lt (StringMap.add varname !new_varname rename)))
                        | Application(lt1, lt2) -> 
                            create_app (barendregt_rec lt1 rename) (barendregt_rec lt2 rename)
                        | Int _ -> lt
                        | Add (a,b) -> create_add (barendregt_rec a rename) (barendregt_rec b rename)
                        | Sub (a,b) -> create_sub (barendregt_rec a rename) (barendregt_rec b rename)
                        | Liste lt_l -> 
                            let evaluate_liste = 
                                List.map
                                    (function x -> (barendregt_rec x rename))
                                    lt_l
                            in
                                create_liste evaluate_liste
                        | Head lt_l -> create_head (barendregt_rec lt_l rename)
                        | Tail lt_l -> create_tail (barendregt_rec lt_l rename)
                        | Cons (elt,lt_l) -> create_cons (barendregt_rec elt rename) (barendregt_rec lt_l rename)
                        | IfZte (cond,conseq,alt) -> create_ifZte (barendregt_rec cond rename) (barendregt_rec conseq rename) (barendregt_rec alt rename)
                        | IfEte (cond,conseq,alt) -> create_ifEte (barendregt_rec cond rename) (barendregt_rec conseq rename) (barendregt_rec alt rename)
                        | Fix lt -> create_fix (barendregt_rec lt rename) 
                        | Let (var,expr, corps) -> create_let var (barendregt_rec expr rename)  (barendregt_rec corps rename) 
                        | Ref lt_ref -> 
                            if List.mem lt_ref !refs_renamed 
                            then lt
                            else (refs_renamed := lt_ref::!refs_renamed; 
                                  lt_ref := barendregt_rec !lt_ref rename; 
                                  lt)
                        | Deref lt -> create_deref (barendregt_rec lt rename)
                        | Assign (lt_ref, lt) -> create_assign (barendregt_rec lt_ref rename) (barendregt_rec lt rename)
                        | Unit -> create_unit
                in    
                    barendregt_rec lt StringMap.empty;;

(* Function that remplaces all free occurences of variable by lambda_terme *)
let instantie lt varname rempl =
    let refs_instantied = ref []
    in
        let rec instantie_rec lt varname rempl =
            match lt with
                Var(name) -> 
                    if name = varname 
                    then rempl
                    else lt
                | Abstraction(var,corps) ->
                    if var = varname
                    then lt
                    else create_abs var (instantie_rec corps varname rempl)
                | Application(lt1, lt2) ->
                    create_app (instantie_rec lt1 varname rempl) (instantie_rec lt2 varname rempl)
                | Int _ -> lt
                | Add (a,b) -> create_add (instantie_rec a varname rempl) (instantie_rec b varname rempl)
                | Sub (a,b) -> create_sub (instantie_rec a varname rempl) (instantie_rec b varname rempl)
                | Liste lt_l ->
                    create_liste (List.map (function x -> instantie_rec x varname rempl) lt_l)
                | Head lt_l -> create_head (instantie_rec lt_l varname rempl)
                | Tail lt_l -> create_tail (instantie_rec lt_l varname rempl)
                | Cons (elt,lt_l) -> create_cons (instantie_rec elt varname rempl) (instantie_rec lt_l varname rempl)
                | IfZte (cond,conseq,alt) -> create_ifZte (instantie_rec cond varname rempl) (instantie_rec conseq varname rempl) (instantie_rec alt varname rempl)
                | IfEte (cond,conseq,alt) -> create_ifEte (instantie_rec cond varname rempl) (instantie_rec conseq varname rempl) (instantie_rec alt varname rempl)
                | Fix f -> create_fix (instantie_rec f varname rempl)
                | Let (var,expr,corps) ->
                    if var=varname
                    then lt
                    else create_let var (instantie_rec expr varname rempl) (instantie_rec corps varname rempl)
                | Ref lt_ref ->
                    if List.mem lt_ref !refs_instantied 
                    then lt
                    else (refs_instantied := lt_ref::!refs_instantied; 
                          lt_ref := instantie_rec !lt_ref varname rempl; 
                          lt)
                | Deref lt -> create_deref (instantie_rec lt varname rempl)
                | Assign (lt_ref, lt) -> create_assign (instantie_rec lt_ref varname rempl) (instantie_rec lt varname rempl)
                | Unit -> create_unit
        in
            instantie_rec lt varname rempl;;        

(* Function that verify if lambda temre is reduced *)
let rec isReduced lt = 
    match lt with
        Application(Abstraction(_,_), _) -> false
        | Var _ -> true
        | Abstraction _ -> true
        | Int _ -> true
        | Unit -> true
        | Application(func, argument) -> (isReduced func) && (isReduced argument)
        | Liste lt_l -> List.for_all isReduced lt_l
        | Ref lt_ref -> isReduced !lt_ref        
        | _ -> false;; 

(* Function that make step of reduction of lambda term *)
let rec ltrcbv_etape lt =
    match lt with
        Application(Abstraction(name,corps), argument) ->
            let eval_arg = ltrcbv_etape argument
            in
                barendregt (instantie corps name eval_arg)
        | Application(func, argument) ->
            let eval_func = ltrcbv_etape func
            and eval_arg = ltrcbv_etape argument
            in
                (match eval_func with
                    Abstraction(name, corps) -> barendregt (instantie corps name eval_arg)
                    | _ -> create_app eval_func eval_arg )
        | Add (a,b) -> 
            let eval_a = evaluate a
            and eval_b = evaluate b
            in
                (match eval_a,eval_b with
                    Int a, Int b -> Int (a+b)
                    | _ -> raise (Evaluation_exc "Argument of '+' is not int"))
        | Sub (a,b) ->
            let eval_a = evaluate a
            and eval_b = evaluate b
            in
                (match eval_a,eval_b with
                    Int a, Int b -> Int (a-b)
                    | _ -> raise (Evaluation_exc "Argument of '-' is not int"))
        | Liste lt_l -> create_liste (List.map evaluate lt_l)
        | Head lt_l ->
            let eval_liste = evaluate lt_l
            in
                (match eval_liste with
                    Liste lt_l -> if lt_l = []
                                  then raise (Evaluation_exc "Argument of 'head' is empty list")
                                  else List.hd lt_l
                    | _ -> raise (Evaluation_exc "Argument of 'head' is not list"))
        | Tail lt_l ->
            let eval_liste = evaluate lt_l
            in
                (match eval_liste with
                    Liste lt_l -> if lt_l = []
                                  then raise (Evaluation_exc "Argument of 'tail' is empty list")
                                  else create_liste (List.tl lt_l)
                    | _ -> raise (Evaluation_exc "Argument of 'tail' is not list"))
        | Cons (elt,lt_l) ->
            let eval_elt = ltrcbv_etape elt
            and eval_liste = evaluate lt_l
            in
                (match eval_liste with
                    Liste lt_l -> create_liste (eval_elt::lt_l)
                    | _ -> raise (Evaluation_exc "Argument of 'cons' is not list"))
        | IfZte (cond,conseq,alt) ->
            let eval_cond = evaluate cond
            in
                (match eval_cond with
                    Int i -> if i=0
                             then ltrcbv_etape conseq
                             else ltrcbv_etape alt
                    | _ -> raise (Evaluation_exc "Condition is not int"))
        | IfEte (cond,conseq,alt) ->
            let eval_cond = evaluate cond
            in
                (match eval_cond with
                    Liste lt_l -> if lt_l=[]
                                  then ltrcbv_etape conseq
                                  else ltrcbv_etape alt
                    | _ -> raise (Evaluation_exc "Condition is not list"))
        | Fix f ->
            (match f with
                Abstraction (var,corps) -> instantie corps var (create_fix f)
                | _ -> raise (Evaluation_exc "Fix couldn't be applied on this terme"))
        | Let (varname,expr,corps) ->
            let eval_expr = evaluate expr
            in
                ltrcbv_etape (instantie corps varname eval_expr) 
        | Ref lt_ref -> 
            if isReduced !lt_ref
            then lt
            else (lt_ref := evaluate !lt_ref;
                  lt)
        | Deref lt ->
            let eval_lt = evaluate lt
            in
                (match eval_lt with
                    Ref lt -> ltrcbv_etape !lt
                    | _ -> raise (Evaluation_exc "Deref (!) couldn't be applied on this terme"))
        | Assign (lt_ref,lt) ->
            let eval_lt_ref = evaluate lt_ref
            and eval_lt = evaluate lt
            in
                (match eval_lt_ref with
                    Ref lt -> lt := eval_lt; create_unit
                    | _ -> raise (Evaluation_exc "First argument of assign (:=) is not a refernece"))
        | x -> x
(* Function that evaluate lambda term untill it couldn't be reduced more *)
and evaluate lt =
    let eval_lt = ref lt
    and start_time = Unix.time ()
    in
        while not (isReduced !eval_lt)
                  && (Unix.time ()) -. start_time < 0.2 do
            eval_lt := ltrcbv_etape !eval_lt;
            reset_gen ();
        done;
        if not (isReduced !eval_lt)
        then raise (Evaluation_exc ("Terme " ^ string_of_lterme lt ^ " is divergent"))
        else !eval_lt

(* Main function of evaluateur *)
let evaluateur lt =
    try
        let lt_res = evaluate lt
        in
            Printf.printf "Result of %s is : \n   %s" (string_of_lterme lt) (string_of_lterme lt_res)
    with Evaluation_exc mess -> Printf.printf "\nTerm %s is couldn't be evaluate : %s" (string_of_lterme lt) mess;;  
