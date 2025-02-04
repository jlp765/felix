open Flx_util
open Flx_ast
open Flx_types
open Flx_btype
open Flx_bparameter
open Flx_bbdcl
open Flx_set
open Flx_mtypes2
open Flx_print
open Flx_typing
open Flx_unify
open Flx_exceptions
open List
open Flx_generic
open Flx_tpat
open Flx_name_map
open Flx_bid
open Flx_bind_reqs
open Flx_bbind_state

let debug = false

let showpasses = 
  try let _ = Sys.getenv "FLX_COMPILER_SHOW_BINDING_PASSES" in true
  with Not_found -> false


let hfind msg h k =
  try Flx_sym_table.find h k
  with Not_found ->
    print_endline ("flx_bbind Flx_sym_table.find failed " ^ msg);
    raise Not_found


let rec fix_typeofs state bsym_table t = 
  match t with
  | BTYP_typeof (symbol_index,expr) ->
print_endline ("fix_typeofs: Found typeof to fix: " ^ Flx_btype.st t ^ "=" ^ Flx_print.sbt bsym_table t);
    let env = Flx_lookup.build_env
      state.lookup_state bsym_table (Some symbol_index)
    in
    let be = Flx_lookup.bind_expression
      state.lookup_state bsym_table env expr
    in
    let typ = snd be in
print_endline ("fix_typeofs: Fixed typeof : " ^ Flx_btype.st t ^ ", set to " ^ Flx_btype.st typ);
    typ
  | _ -> Flx_btype.map ~f_btype:(fix_typeofs state bsym_table) t



let bbind (state:Flx_bbind_state.bbind_state_t) start_counter ref_counter bsym_table =
if showpasses then
print_endline ("Flx_bbind.bbind *********************** " ^ string_of_int (Flx_bsym_table.length bsym_table));
  (* loop through all counter values [HACK] to get the indices in sequence, AND,
   * to ensure any instantiations will be bound, (since they're always using the
   * current value of state.counter for an index. Note that in the process of
   * binding new symbols can be added to the end of the table, so the terminating
   * index is not known in advance. It had better converge!
   *)
  (* PASS 0, TYPEDEFS ONLY *)

if showpasses then
print_endline ("\n====================\nPASS 1 PLAIN BINDING: Setting type aliases to nominal\n===============\n");
  let saved_env_cache = Hashtbl.copy state.lookup_state.Flx_lookup_state.env_cache in
  let saved_visited = Hashtbl.copy state.visited in

  let counter = ref start_counter in
  while !counter < !ref_counter do
    let i = !counter in
    if Hashtbl.mem state.visited i then 
    begin 
(*
      print_endline ("Skipping already processed typedef " ^ string_of_int i);
*)
     () 
    end
    else
    begin match
      try Some (Flx_sym_table.find_with_parent state.sym_table i)
      with Not_found -> None
    with
    | None -> (* print_endline "bbind: Symbol not found"; *) ()
    | Some (parent, sym) ->
(*
print_endline ("[flx_bbind] bind_symbol " ^ sym.Flx_sym.id ^ "??");
*)
      begin match sym.Flx_sym.symdef with
      | Flx_types.SYMDEF_type_function  (_,t) 
      ->
        begin try
(*
        print_endline ("Binding typefun " ^ sym.Flx_sym.id ^ "<"^string_of_int i^"> = " ^ string_of_typecode t);
*)
                begin try Flx_bind_symbol.bbind_symbol state bsym_table i parent sym
                with Not_found ->
                  try match hfind "bbind" state.sym_table i with { Flx_sym.id=id } ->
                    print_endline ("Binding error, Not_found thrown binding " ^ id ^ " index " ^
                      string_of_bid i ^ " parent " ^ (match parent with | None -> "NONE" | Some p -> string_of_int p))
                  with Not_found ->
                    failwith ("Binding error, Not_found thrown binding unknown id with index " ^ string_of_bid i)
                end
        with _ -> ()
        end

      | Flx_types.SYMDEF_type_alias  t
      ->
        begin try
(*
        print_endline ("Binding typedef " ^ sym.Flx_sym.id ^ "<"^string_of_int i^"> = " ^ string_of_typecode t);
*)
                begin try Flx_bind_symbol.bbind_symbol state bsym_table i parent sym
                with Not_found ->
                  try match hfind "bbind" state.sym_table i with { Flx_sym.id=id } ->
                    print_endline ("Binding error, Not_found thrown binding " ^ id ^ " index " ^
                      string_of_bid i ^ " parent " ^ (match parent with | None -> "NONE" | Some p -> string_of_int p))
                  with Not_found ->
                    failwith ("Binding error, Not_found thrown binding unknown id with index " ^ string_of_bid i)
                end
        with _ -> ()
        end
      | _ -> ()
      end
    end;
    incr counter
  done
  ;
(*
  print_endline ("\n=====================\n TYPEDEFS before expansion\n=====================\n");
  Flx_bsym_table.iter (fun bid parent bsym ->
    let bbdcl = Flx_bsym.bbdcl bsym in
    match bbdcl with
    | BBDCL_type_function _ 
    | BBDCL_nominal_type_alias _ -> print_endline (bsym.id ^ "    typedef " ^ string_of_int bid ^ " -> " ^
      Flx_print.string_of_bbdcl bsym_table bbdcl bid)
    | _ -> ()
  ) bsym_table;  
  print_endline ("\n==========================================\n");
*)
(*
  print_endline ("\n=====================\n VAR CACHE (function codomains) \n=====================\n");
  Hashtbl.iter (fun i t ->
    print_endline ("type var " ^ string_of_int i ^ " -> " ^ Flx_btype.st t);
  )
  state.varmap;
*)
(*
  Hashtbl.clear state.varmap;
  Hashtbl.clear state.virtual_to_instances;
  Hashtbl.clear state.instances_of_typeclass;
  Hashtbl.clear state.lookup_state.generic_cache;
*)
(*
  print_endline ("\n=====================\nTYPE CACHE \n=====================\n");
  Hashtbl.iter (fun i t ->
    print_endline ("type of index " ^ string_of_int i ^ " -> " ^ Flx_btype.st t);
  )
  state.ticache;
*)
 
  state.visited <-saved_visited;
  state.lookup_state.Flx_lookup_state.env_cache <- saved_env_cache;

if showpasses then
  print_endline ("\n===================\nSetting type aliases to structural\n=======================\n");

  (* PASS 1, TYPE ONLY *)

if showpasses then
  print_endline ("\n===================\nFixing typeofs \n=======================\n");


  Flx_bsym_table.iter (fun bid parent bsym ->
    let bbdcl = Flx_bsym.bbdcl bsym in
    let sr = Flx_bsym.sr bsym in
    match bbdcl with
    | BBDCL_type_alias (bvs,t) -> 
      let r = fix_typeofs state bsym_table t in 
      let b = bbdcl_type_alias (bvs, r) in 
      Flx_bsym_table.update_bbdcl bsym_table bid b

    | BBDCL_type_function (bks,t) -> 
      let r = fix_typeofs state bsym_table t in 
      let b = bbdcl_type_function (bks, r) in 
      Flx_bsym_table.update_bbdcl bsym_table bid b
 
    | _ -> ()
  ) bsym_table;
(*
print_endline ("Done fixing typeofs");
*)
if showpasses then
  print_endline ("\n===================\nBinding nominal types \n=======================\n");
  let counter = ref start_counter in
  while !counter < !ref_counter do
    let i = !counter in
    begin match
      try Some (Flx_sym_table.find_with_parent state.sym_table i)
      with Not_found -> None
    with
    | None -> (* print_endline "bbind: Symbol not found"; *) ()
    | Some (parent, sym) ->
(*
print_endline ("[flx_bbind] bind_symbol " ^ sym.Flx_sym.id ^ "??");
*)
      begin match sym.Flx_sym.symdef with
      | Flx_types.SYMDEF_union _
      | Flx_types.SYMDEF_struct _
      | Flx_types.SYMDEF_cstruct _ 
      | Flx_types.SYMDEF_abs _ 
      | Flx_types.SYMDEF_const_ctor _
      | Flx_types.SYMDEF_nonconst_ctor _
      | Flx_types.SYMDEF_newtype _
      ->
        begin try Flx_bind_symbol.bbind_symbol state bsym_table i parent sym
        with Not_found ->
          try match hfind "bbind" state.sym_table i with { Flx_sym.id=id } ->
            failwith ("Binding error, Not_found thrown binding " ^ id ^ " index " ^
              string_of_bid i ^ " parent " ^ (match parent with | None -> "NONE" | Some p -> string_of_int p))
          with Not_found ->
            failwith ("Binding error, Not_found thrown binding unknown id with index " ^ string_of_bid i)
        end
      | _ -> ()
      end
    end;
    incr counter
  done
  ;

if showpasses then
  print_endline ("\n===================\nHandling Subtyping Coercions\n=======================\n");
  (* PASS 2, SUBTYPE COERCIONS ONLY *)
  let counter = ref start_counter in
  while !counter < !ref_counter do
    let i = !counter in
    begin match
      try Some (Flx_sym_table.find_with_parent state.sym_table i)
      with Not_found -> None
    with
    | None -> (* print_endline "bbind: Symbol not found"; *) ()
    | Some (parent, sym) ->
(*
print_endline ("[flx_bbind] bind_symbol " ^ sym.Flx_sym.id ^ "??");
*)
      let sr = sym.Flx_sym.sr in
      let vs = fst sym.Flx_sym.vs in
      begin match sym.Flx_sym.symdef with
      | SYMDEF_function (params,ret,effect,props,_) when List.mem `Subtype props ->
        let dom, cod = 
          let ps = fst params in
          begin match ps with
          | Satom (sr,kind,id,typ,initopt) -> typ,ret 
          | _ ->
             clierr sr ("Improper subtype, only one parameter allowed, got " ^ 
               string_of_paramspec_t ps)
          end
        in
        begin
          begin
            try Flx_bind_symbol.bbind_symbol state bsym_table i parent sym
            with Not_found ->
              try match hfind "bbind" state.sym_table i with { Flx_sym.id=id } ->
                failwith ("Binding error, Not_found thrown binding " ^ id ^ " index " ^
                  string_of_bid i ^ " parent " ^ (match parent with | None -> "NONE" | Some p -> string_of_int p))
              with Not_found ->
                failwith ("Binding error, Not_found thrown binding unknown id with index " ^ string_of_bid i)
          end;
          (* now, bind the types dom,cod! We cheat, and just lookup the cache*)
(*
          print_endline ("bind dom/cod");
*)
          let ft =
             try Hashtbl.find state.ticache i 
             with Not_found -> failwith ("WOOPS, expected type of subtype function in cache");
          in
(*
          print_endline ("Type of function " ^ string_of_int i ^ " is " ^ sbt bsym_table ft);
*)
          match ft with
          | BTYP_function (BTYP_inst (`Nominal _, dom,_,_),BTYP_inst (`Nominal _, cod,_,_)) ->
(*
            print_endline ("Domain index = " ^ string_of_int dom ^ " codomain index = " ^ string_of_int cod);
*)
            Flx_bsym_table.add_supertype bsym_table ((cod,dom),i)
 
          | BTYP_function (BTYP_ptr (`RW, BTYP_inst (`Nominal _, dom,_,_), []),BTYP_ptr(`RW, BTYP_inst (`Nominal _, cod,_,_),[])) ->
            print_endline ("Pointer coercion: Domain index = " ^ string_of_int dom ^ " codomain index = " ^ string_of_int cod);

            Flx_bsym_table.add_pointer_supertype bsym_table ((cod,dom),i)
          | _ -> clierr sr ("Subtype specification requires function from and to nominal type or pointers thereto")
        end

      | SYMDEF_fun (props,ps,ret,_,_,_) when List.mem `Subtype props ->
(*
        if List.length vs <> 0 then
          print_endline ("   Improper subtype, no type variables allowed, got " ^
           string_of_int (List.length vs))
        else
*)
        let dom, cod = 
          begin match ps with
          | [typ] -> typ,ret
          | _ ->
             clierr sr ("Improper subtype, only one parameter allowed, got " ^ 
               string_of_int (List.length ps))
          end
        in
        begin 
          begin
            try Flx_bind_symbol.bbind_symbol state bsym_table i parent sym
            with Not_found ->
              try match hfind "bbind" state.sym_table i with { Flx_sym.id=id } ->
                failwith ("Binding error, Not_found thrown binding " ^ id ^ " index " ^
                  string_of_bid i ^ " parent " ^ (match parent with | None -> "NONE" | Some p -> string_of_int p))
              with Not_found ->
                failwith ("Binding error, Not_found thrown binding unknown id with index " ^ string_of_bid i)
          end;
          (* now bind the types dom,cod *)
(*
          print_endline ("bind dom/cod");
*)
          let ft =
             try Hashtbl.find state.ticache i 
             with Not_found -> failwith ("WOOPS, expected type of subtype function in cache");
          in
(*
          print_endline ("Type of function " ^ string_of_int i ^ " is " ^ sbt bsym_table ft);
*)
          match ft with
          | BTYP_function (BTYP_inst (`Nominal _, dom,_,_),BTYP_inst (`Nominal _, cod,_,_)) ->
(*
            print_endline ("Domain index = " ^ string_of_int dom ^ " codomain index = " ^ string_of_int cod);
*)
            Flx_bsym_table.add_supertype bsym_table ((cod,dom),i)
          | BTYP_function (BTYP_ptr (`RW, BTYP_inst (`Nominal _, dom,_,_), []),BTYP_ptr(`RW, BTYP_inst (`Nominal _, cod,_,_),[])) ->
            print_endline ("Pointer coercion: Domain index = " ^ string_of_int dom ^ " codomain index = " ^ string_of_int cod);

            Flx_bsym_table.add_pointer_supertype bsym_table ((cod,dom),i)
          | _ -> clierr sr ("Subtype specification requires function from and to nominal types")
        end
      | _ -> ()
      end (* symdef *)
    end; (* parent *)
    incr counter
  done
  ;

if showpasses then
  print_endline ("\n===================\nBinding non-deferred functions\n=======================\n");
  (* PASS 3, NON DEFERRED FUNCTIONS *)
  let defered = ref [] in
  let counter = ref start_counter in
  while !counter < !ref_counter do
    let i = !counter in
    begin match
      try Some (Flx_sym_table.find_with_parent state.sym_table i)
      with Not_found -> None
    with
    | None -> (* print_endline "bbind: Symbol not found"; *) ()
    | Some (parent, sym) ->
(*
print_endline ("[flx_bbind] bind_symbol " ^ sym.Flx_sym.id ^ "??");
*)
(*
print_endline ("[flx_bbind] bind_symbol " ^ sym.Flx_sym.id ^ " .. BINDING: calling BBIND_SYMBOL");
print_endline ("Binding symbol " ^ symdef.Flx_sym.id ^ "<" ^ si i ^ ">"); 
*)
      try Flx_bind_symbol.bbind_symbol state bsym_table i parent sym
      with Not_found ->
        try match hfind "bbind" state.sym_table i with { Flx_sym.id=id } ->
          failwith ("Binding error, Not_found thrown binding " ^ id ^ " index " ^
            string_of_bid i ^ " parent " ^ (match parent with | None -> "NONE" | Some p -> string_of_int p))
        with Not_found ->
          failwith ("Binding error, Not_found thrown binding unknown id with index " ^ string_of_bid i)
    end;
    incr counter
  done
  ;

if showpasses then
  print_endline ("\n===================\nBinding deferred functions\n=======================\n");
  (* PASS 4 DEFERRED FUNCTIONS *)
if (List.length (!defered) <> 0) then begin
print_endline ("DEFERED PROCESSING STARTS");

  List.iter (fun i ->
    begin match
      try Some (Flx_sym_table.find_with_parent state.sym_table i)
      with Not_found -> None
    with
    | None -> (* print_endline "bbind: Symbol not found"; *) ()
    | Some (parent, sym) ->
print_endline ("[flx_bbind] DEFERED bind_symbol " ^ sym.Flx_sym.id ^ "?? calling BBIND_SYMBOL");
      try Flx_bind_symbol.bbind_symbol state bsym_table i parent sym
      with Not_found ->
        try match hfind "bbind" state.sym_table i with { Flx_sym.id=id } ->
          failwith ("Binding error, Not_found thrown binding " ^ id ^ " index " ^
            string_of_bid i)
        with Not_found ->
          failwith ("Binding error, Not_found thrown binding unknown id with index " ^ string_of_bid i)
    end
  )
  (!defered)
  ;
print_endline ("DEFERED PROCESSING ENDS");

end;

if showpasses then
print_endline ("\n===================\nBETA EVERYTHING \n=======================\n");

Flx_bsym_table.iter 
  (fun bid parent bsym ->
    let f_btype t = Flx_beta.beta_reduce "Global beta reduction" state.counter bsym_table  Flx_srcref.dummy_sr t in
    let rec f_bexpr e =  Flx_bexpr.map ~f_btype ~f_bexpr e in
    let f_bexe exe = Flx_bexe.map ~f_btype ~f_bexpr exe in 
    let bbdcl = Flx_bbdcl.map ~f_btype ~f_bexe ~f_bexpr bsym.bbdcl in
    let bsym = Flx_bsym.replace_bbdcl bsym bbdcl in 
    Flx_bsym_table.update bsym_table bid bsym
  ) bsym_table
;

if showpasses then
print_endline ("\n===================\nBINDING COMPLETE \n=======================\n")

