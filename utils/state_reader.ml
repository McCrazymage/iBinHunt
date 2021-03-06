(** Owned and copyright BitBlaze, 2008. All rights reserved.
 Do not copy, disclose, or distribute without explicit written
 permission.
*)
(**
  A driver to read state files generated by TEMU

   @author Juan Caballero
*)

open Vine
open Vine_util
open Temu_state

type cmdlineargs_t = {
  mutable in_state_file : string;
  mutable in_state_ranges : (int64 * int64) list;
  mutable out_meminits : string;
  mutable out_dumps_pid : int;
  mutable out_ranges_file : string;
} ;;

let page_size = 4096L
let layer_id = 0

(* Get the start address of the memory page containing the given address *)
let page_start addr = 
  Int64.mul (Int64.div addr page_size) page_size

(* Get list of pages that comprise a range *)
let get_page_list first last = 
  let first_page = page_start first in
  let rec add_page acc curr_start = 
    let next_page = Int64.add curr_start page_size in
    if (next_page > last) then List.rev acc
    else add_page (next_page :: acc) next_page
  in
  add_page [first_page] first_page


(* Generate a raw dump file for each memory page in given ranges *) 
let generate_raw_dump pid filename ranges =
  let ic = open_in filename in
  let blkinfo_l = read_block_info ic in
  let process_range ((first:int64), (last:int64)) =
    let page_l = get_page_list first last in
    let process_page page_start = 
      let page_end = Int64.pred (Int64.add page_start page_size) in
      let data = 
	read_memory_range 
	  (Int64.to_int32 page_start) 
	  (Int64.to_int32 page_end) 
	  blkinfo_l 
	  ic 
      in
      let num_bytes = List.length data in
      (* Printf.printf "Num_bytes: %d\n"  num_bytes; *)
      (* Printf.printf "0x%08Lx -> 0x%08Lx\n" page_start page_end; *)
      if (num_bytes > 0) then (
	let filename = 
	  Printf.sprintf "dump_%d_%08Lx_%d_%08Lx.bin" 
	    pid page_start layer_id page_end
	in
	let oc = open_out filename in
	let ioc = IO.output_channel oc in
	List.iter (fun b -> IO.write ioc b) data;
	let _ = IO.close_out ioc in
	close_out oc
      )
    in
    List.iter process_page page_l;
  in
  List.iter process_range ranges;
  close_in ic



(* Parse the command line arguments *)
let parse_cmdline =
  let cmdlineargs = {
    in_state_file = "";
    in_state_ranges = [];
    out_meminits = "";
    out_dumps_pid = 0;
    out_ranges_file = "";
  } 
  in
  let progname = Sys.argv.(0) in
  let usage = "USAGE: Check " ^ progname ^ " -help" in
  let add_state_range s =
    Scanf.sscanf s "0x%Lx:0x%Lx" (fun x y -> 
      cmdlineargs.in_state_ranges <- (x,y)::cmdlineargs.in_state_ranges)
  in
  let ignore_arg x = () in
  let rec arg_spec =
    ("-in-state", Arg.String (fun s -> cmdlineargs.in_state_file <- s),
      "<file> File containing TEMU state")
    ::("-in-state-range", Arg.String add_state_range,
      "<0xDEAD:0xBEEF> Memory range startAddr:EndAddr (inclusive)")
    ::("-out-dumps", Arg.Int (fun i -> cmdlineargs.out_dumps_pid <- i),
	"<pid> PID of the process. Generates a raw dump file per memory page")
    ::("-out-meminits", Arg.String (fun s -> cmdlineargs.out_meminits <- s),
	"<file> File to output Vine memory initializers for given ranges")
    ::("-out-ranges", Arg.String (fun s -> cmdlineargs.out_ranges_file <- s),
	"<file> File to output all ranges in state file (without content)")
    ::[]
  in
  let _ = Arg.parse arg_spec ignore_arg usage in
  cmdlineargs
;;

(* main *)
let main () =
  (* Parse arguments *)
  let args = parse_cmdline in

  (* Create a memory variable *)
  let arr_t = (Array(REG_8,(Vine.array_idx_type_to_size REG_32))) in
  let arr_name = "mem_arr" in
  let memvar = Vine.newvar arr_name arr_t in

  (* Read all ranges in state file *)
  let blkinfo = 
    if (args.in_state_file <> "") then read_memory_ranges args.in_state_file
    else (
      Printf.fprintf stderr "Need to provide state file\n";
      exit 1
    )
  in

  (* Output all ranges in state file *)
  if (args.out_ranges_file  <> "") then (
    let oc = open_out args.out_ranges_file in
    List.iter (fun b -> Printf.fprintf oc "0x%lx -> 0x%lx\n" b.first b.last) 
      blkinfo;
    exit 0;
  );

  (* Read ranges *)
  let mem_inits_sl = 
    if ((args.in_state_file <> "") && (List.length args.in_state_ranges >= 1)) 
      then Temu_state.generate_range_inits args.in_state_file 
	args.in_state_ranges memvar
    else []
  in
  let mem_inits_sl = List.rev mem_inits_sl in

  (* Output meminits file *)
  if (args.out_meminits <> "") then (
    let oc = open_out args.out_meminits in
    let num_inits = List.length mem_inits_sl in
    if (num_inits > 0) then (
      let prog = ([memvar],mem_inits_sl) in
      Vine.pp_program (output_string oc) prog;
      if (oc <> stdout) then close_out oc
    )
    else Printf.fprintf stdout "No statements found\n";
  );

  (* Output dumps files *)
  if (args.out_dumps_pid <> 0) then (
    generate_raw_dump args.out_dumps_pid args.in_state_file args.in_state_ranges
  );

  exit 0
;;

  main ();;

