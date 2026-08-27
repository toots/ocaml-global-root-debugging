(* Checking between steps says which one damaged a root. Left alone, the next
   collection reports it from wherever it happens to run. *)

external decoder_open : int -> unit = "tgr_decoder_open"
external metadata_open : string -> unit = "tgr_metadata_open"
external damage_a_root : unit -> unit = "tgr_damage_a_root"

let step name f =
  f ();
  Gc.check_roots ();
  Printf.printf "%s: roots intact\n%!" name

let () =
  step "opened the decoder" (fun () -> decoder_open 4);
  step "read the metadata" (fun () -> metadata_open "utf-8");
  step "ran the codec" damage_a_root;
  print_endline "not reached"
