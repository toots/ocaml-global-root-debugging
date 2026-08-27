#define CAML_INTERNALS

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/skiplist.h>
#include <caml/globroots.h>

#include <dlfcn.h>
#include <stdlib.h>

extern struct skiplist caml_global_roots;

/* A binding that keeps one OCaml callback alive per channel, the way a decoder
   or a resolver does. */

typedef struct {
  int channels;
  value *handler;               /* one root per channel */
} decoder;

static decoder dec;

/* Not static: a root is worth nothing to triage if the name it carries cannot
   be resolved. */
void decoder_alloc(int channels)
{
  dec.channels = channels;
  dec.handler = malloc(channels * sizeof(value));
  for (int i = 0; i < channels; i++) {
    dec.handler[i] = Val_unit;
    caml_register_global_root(&dec.handler[i]);
  }
}

/* The bug: the table goes back to the allocator with the roots still registered
   on it, and the pointer is kept. */
void decoder_close(void)
{
  free(dec.handler);
}

/* Whatever the allocator has since put there is written over. */
void decoder_flush(int channels)
{
  for (int i = 0; i < channels; i++)
    dec.handler[i] = Val_unit;
}

CAMLprim value tgr_decoder_open(value channels)
{
  decoder_alloc(Int_val(channels));
  return Val_unit;
}

CAMLprim value tgr_decoder_close(value unit)
{
  (void) unit;
  decoder_close();
  return Val_unit;
}

CAMLprim value tgr_decoder_flush(value channels)
{
  decoder_flush(Int_val(channels));
  return Val_unit;
}

/* A second binding, so that a root can be traced back to one of two owners. */

static value metadata_charset;

void metadata_open(value v)
{
  metadata_charset = v;
  caml_register_global_root(&metadata_charset);
}

CAMLprim value tgr_metadata_open(value v)
{
  metadata_open(v);
  return Val_unit;
}

/* Triage: what registered the root at this address. */
static value origin_of(value *r)
{
  void *pc = caml_global_root_origin(r);
  Dl_info info;
  const char *name = "unknown";
  if (pc != NULL && dladdr(pc, &info) != 0 && info.dli_sname != NULL)
    name = info.dli_sname;
  return caml_copy_string(name);
}

CAMLprim value tgr_decoder_origin(value unit)
{
  (void) unit;
  return origin_of(&dec.handler[0]);
}

CAMLprim value tgr_metadata_origin(value unit)
{
  (void) unit;
  return origin_of(&metadata_charset);
}

/* Stands in for the stray write, so that the post-mortem example has something
   to find. What a use-after-free or an overrun does to a cell varies with the
   allocator; what it leaves behind does not. */
CAMLprim value tgr_damage_a_root(value unit)
{
  (void) unit;
  FOREACH_SKIPLIST_ELEMENT(e, &caml_global_roots, {
      if (e->key == (uintnat) &metadata_charset) {
        e->key |= (uintnat) 1 << 48;
        break;
      }
    })
  return Val_unit;
}

/* A root whose storage a binding has freed reads whatever now occupies it.
   Standing in for that, since what a freed block holds is the allocator's
   business: something that is not a value, and not a mapped address either. */
CAMLprim value tgr_root_holds_rubbish(value unit)
{
  (void) unit;
  metadata_charset = (value) 0x10;
  return Val_unit;
}
