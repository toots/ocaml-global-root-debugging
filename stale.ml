(* A root holding something that is no longer a value. Nothing about the root
   lists is wrong, so the checks pass and the collector follows it down. *)

external metadata_open : string -> unit = "tgr_metadata_open"
external root_holds_rubbish : unit -> unit = "tgr_root_holds_rubbish"

let () =
  metadata_open "utf-8";
  root_holds_rubbish ();
  print_endline "the root holds rubbish; collecting";
  Gc.full_major ();
  print_endline "not reached"
