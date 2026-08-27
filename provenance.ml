(* Two bindings keep OCaml values alive. Asking which one owns a given root is
   what turns an address in a crash report into a place to look. *)

external decoder_open : int -> unit = "tgr_decoder_open"
external metadata_open : string -> unit = "tgr_metadata_open"
external decoder_origin : unit -> string = "tgr_decoder_origin"
external metadata_origin : unit -> string = "tgr_metadata_origin"

let () =
  decoder_open 256;
  metadata_open "utf-8";
  Printf.printf "the decoder's first root was registered by %s\n"
    (decoder_origin ());
  Printf.printf "the metadata root was registered by %s\n" (metadata_origin ())
