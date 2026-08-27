(* What a program does when a root has been damaged: it dies in the collector,
   a long way from whatever did the damage. The core is then all there is. *)

external metadata_open : string -> unit = "tgr_metadata_open"
external damage_a_root : unit -> unit = "tgr_damage_a_root"

let () =
  metadata_open "utf-8";
  damage_a_root ();
  print_endline "a root has been damaged; collecting";
  Gc.full_major ();
  print_endline "not reached"
