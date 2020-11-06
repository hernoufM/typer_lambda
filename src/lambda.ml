type lambda_terme = 
    Var of string
    | Abstraction of string * lambda_terme 
    | Application of lambda_terme  * lambda_terme
    | Int of int;;

let rec string_of_lterme lt =
    match lt with
        Var name -> name
        | Abstraction(varname,corps) -> "(λ" ^ varname ^ "." ^ string_of_lterme corps ^ ")"
        | Application(left, right) -> "(" ^ string_of_lterme left ^ " " ^ string_of_lterme right ^ ")"
        | Int i -> string_of_int i;;

let pp_lterme lt = Printf.fprintf stdout "%s" (string_of_lterme lt);;

let create_var name = Var name;;

let create_abs var corps = Abstraction (var, corps);;

let create_app left right = Application (left,right);;

let create_int i = Int i;;

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

module StringMap = Map.Make(String);;
module StringSet = Set.Make(String);;

let barendregt lt =
    let rec barendregt_rec lt rename var_globs =
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
                    create_abs !new_varname (barendregt_rec lt (StringMap.add varname !new_varname rename) var_globs))
            | Application(lt1, lt2) -> 
                create_app (barendregt_rec lt1 rename var_globs) (barendregt_rec lt2 rename var_globs)
            | x -> x
    and variables_globals lt var_libres =
            match lt with
                Var(name) -> 
                    if StringSet.mem name var_libres
                    then StringSet.empty
                    else StringSet.singleton name
                | Abstraction(varname,corps) -> 
                    variables_globals corps (StringSet.add varname var_libres)
                | Application(lt1, lt2) -> 
                    StringSet.union (variables_globals lt1 var_libres) (variables_globals lt2 var_libres)
                | _ -> var_libres
    in
        let var_globs = variables_globals lt StringSet.empty
        in
            barendregt_rec lt StringMap.empty var_globs;;

(* (λx.λy.x) 5 z *)
let lambda_ex = 
    create_app
        (create_app
            (create_abs "x"
                (create_abs "y"
                    (create_var "x")))
            (create_int 5))
        (create_var "z");;

let rec instantie lt varname rempl =
    match lt with
        Var(name) -> 
            if name = varname 
            then rempl
            else lt
        | Abstraction(name,lt) ->
            create_abs name (instantie lt varname rempl)
        | Application(lt1, lt2) ->
            create_app (instantie lt1 varname rempl) (instantie lt2 varname rempl)
        | x -> x;;

(* ((λx.(λy.(x y))) (λy.(y z))) x *)
let lambda_ex2 = 
    create_app 
        (create_app 
            (create_abs "x" 
                (create_abs "y" 
                    (create_app 
                        (create_var "x") 
                        (create_var "y")))) 
            (create_abs "y" 
                (create_app 
                    (create_var "y") 
                    (create_var "z")))) 
        (create_var "x");;

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
        | x -> x;;

(* (λx.x x x) (λx.x x x) *)
let sigma = 
    create_app 
        (create_abs "x" 
            (create_app 
                (create_app 
                    (create_var "x") 
                    (create_var "x")) 
                (create_var "x"))) 
        (create_abs "x" 
            (create_app 
                (create_app 
                    (create_var "x") 
                    (create_var "x")) 
                (create_var "x")))

let reduce_lambda lt = 
    let lambda = ref lt
    and start_time = Unix.time ()
    in
        let rec isReduced lt = 
            match lt with
                Application(Abstraction(_,_), _) -> false
                | Var _ -> true
                | Abstraction _ -> true
                | Application(func, argument) -> (isReduced func) && (isReduced argument)
                | _ -> true 
        in
            while not (isReduced !lambda) && (Unix.time ()) -. start_time < 0.1 do
                lambda := ltrcbv_etape !lambda;
                pp_lterme !lambda;
                reset_gen ();
            done;
            print_newline();
            if not (isReduced !lambda)
            then print_endline "Time is out, lambda is divergent"
            else (print_string "Final lambda is : "; pp_lterme !lambda; print_newline ());;
