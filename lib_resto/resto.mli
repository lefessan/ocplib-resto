(**************************************************************************)
(*  ocplib-resto                                                          *)
(*  Copyright (C) 2016, OCamlPro.                                         *)
(*                                                                        *)
(*    All rights reserved.  This file is distributed under the terms      *)
(*    of the GNU Lesser General Public License version 2.1, with the      *)
(*    special exception on linking described in the file LICENSE.         *)
(*                                                                        *)
(**************************************************************************)

type meth = [ `GET | `POST | `DELETE | `PUT | `PATCH ]

val string_of_meth: [< meth ] -> string
val meth_of_string: string -> [> meth ] option

module MethMap : Map.S with type key = meth
module StringMap : Map.S with type key = string

(** Typed path argument. *)
module Arg : sig

  type 'a t
  type 'a arg = 'a t
  val make:
    ?descr:string ->
    name:string ->
    destruct:(string -> ('a, string) result) ->
    construct:('a -> string) ->
    unit -> 'a arg

  type descr = {
    name: string ;
    descr: string option ;
  }
  val descr: 'a arg -> descr

  val bool: bool arg
  val int: int arg
  val int32: int32 arg
  val int64: int64 arg
  val float: float arg
  val string: string arg

  val like: 'a arg -> ?descr:string -> string -> 'a arg

end


(** Parametrized path to services. *)
module Path : sig

  type ('prefix, 'params) t
  type ('prefix, 'params) path = ('prefix, 'params) t
  type 'prefix context = ('prefix, 'prefix) path

  val root: unit context
  val open_root: 'a context

  val add_suffix:
    ('prefix, 'params) path -> string -> ('prefix, 'params) path
  val (/):
    ('prefix, 'params) path -> string -> ('prefix, 'params) path

  val add_arg:
    ('prefix, 'params) path -> 'a Arg.t -> ('prefix, 'params * 'a) path
  val (/:):
    ('prefix, 'params) path -> 'a Arg.t -> ('prefix, 'params * 'a) path

  val add_final_args:
    ('prefix, 'params) path -> 'a Arg.t -> ('prefix, 'params * 'a list) path
  val (/:*):
    ('prefix, 'params) path -> 'a Arg.t -> ('prefix, 'params * 'a list) path

  val prefix:
    ('prefix, 'a) path -> ('a, 'params) path -> ('prefix, 'params) path

  val map:
    ('a -> 'b) -> ('b -> 'a) -> ('prefix, 'a) path -> ('prefix, 'b) path

end

(** Service directory description *)
module Description : sig

  type request = {
    recurse: bool ;
  }

  type 'schema service = {
    description: string option ;
    path: path_item list ;
    meth: meth ;
    query: query_item list ;
    input: 'schema option ;
    output: 'schema ;
    error: 'schema ;
  }

  and path_item =
    | PStatic of string
    | PDynamic of Arg.descr
    | PDynamicTail of Arg.descr

  and query_item = {
    name: string ;
    description: string option ;
  }

  type 'schema directory =
    | Empty
    | Static of 'schema static_directory
    | Dynamic of string option

  and 'schema static_directory = {
    services: 'schema service MethMap.t ;
    subdirs: 'schema static_subdirectories option ;
  }

  and 'schema static_subdirectories =
    | Suffixes of 'schema directory StringMap.t
    | Arg of Arg.descr * 'schema directory

  val pp_print_directory:
    (* ?pp_schema:(Format.formatter -> 'schema -> unit) -> *) (* TODO ?? *)
    Format.formatter -> 'schema directory -> unit

end

module Query : sig

  type 'a t
  type 'a query = 'a t

  val empty: unit query

  type ('a, 'b) field
  val field:
    ?descr: string ->
    string -> 'a Arg.t -> 'a -> ('b -> 'a) -> ('b, 'a) field

  type ('a, 'b, 'c) open_query
  val query: 'b -> ('a, 'b, 'b) open_query
  val (|+):
    ('a, 'b, 'c -> 'd) open_query ->
    ('a, 'c) field -> ('a, 'b, 'd) open_query
  val seal: ('a, 'b, 'a) open_query -> 'a t

  type untyped = (string * string) list
  exception Invalid of string
  val parse: 'a query -> untyped -> 'a

end

(**/**)

module Internal : sig

  module Ty : sig

    exception Not_equal
    type (_, _) eq = Eq : ('a, 'a) eq

    type 'a id
    val eq : 'a id -> 'b id -> ('a, 'b) eq

  end

  type 'a arg = {
    id: 'a Ty.id;
    destruct: string -> ('a, string) result ;
    construct: 'a -> string ;
    descr: Arg.descr ;
  }

  val from_arg : 'a arg -> 'a Arg.t
  val to_arg : 'a Arg.t -> 'a arg

  type (_, _) rpath =
    | Root : ('rkey, 'rkey) rpath
    | Static : ('rkey, 'key) rpath * string -> ('rkey, 'key) rpath
    | Dynamic : ('rkey, 'key) rpath * 'a arg -> ('rkey, 'key * 'a) rpath
    | DynamicTail : ('rkey, 'key) rpath * 'a arg -> ('rkey, 'key * 'a list) rpath

  type (_, _) path =
    | Path: ('prefix, 'params) rpath -> ('prefix, 'params) path
    | MappedPath:
        ('prefix, 'key) rpath * ('key -> 'params) * ('params -> 'key) ->
      ('prefix, 'params) path

  val from_path : ('a, 'b) path -> ('a, 'b) Path.t
  val to_path : ('a, 'b) Path.t -> ('a, 'b) path

  type 'a query =
    | Fields: ('a, 'b) query_fields * 'b -> 'a query

  and ('a, 'b) query_fields =
    | F0: ('a, 'a) query_fields
    | F1: ('a, 'b) query_field * ('a, 'c) query_fields ->
      ('a, 'b -> 'c) query_fields

  and ('a, 'b) query_field = {
    fname : string ;
    ftype : 'b arg ;
    fdefault : 'b ;
    fget : 'a -> 'b ;
    fdescription : string option ;
  }

  val from_query : 'a query -> 'a Query.t
  val to_query : 'a Query.t -> 'a query

end

(**/**)

module type ENCODING = sig
  type 'a t
  type schema
  val unit : unit t
  val schema : 'a t -> schema
  val description_request_encoding : Description.request t
  val description_answer_encoding : schema Description.directory t
end

module MakeService(Encoding : ENCODING) : sig

  (** Services. *)
  type (+'meth, 'prefix, 'params, 'query, 'input, 'output, 'error) t
    constraint 'meth = [< meth ]
  type (+'meth, 'prefix, 'params, 'query, 'input, 'output, 'error) service =
    ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) t


  val meth:
    ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) service ->
    'meth

  val query:
    ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) service ->
    'query Query.t

  type _ input =
    | No_input : unit input
    | Input : 'input Encoding.t -> 'input input

  val input_encoding:
    ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) service ->
    'input input

  val output_encoding:
    ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) service ->
    'output Encoding.t

  val error_encoding:
    ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) service ->
    'error Encoding.t

  val get_service:
    ?description: string ->
    query: 'query Query.t ->
    output: 'output Encoding.t ->
    error: 'error Encoding.t ->
    ('prefix, 'params) Path.t ->
    ([ `GET ], 'prefix, 'params, 'query, unit, 'output, 'error) service

  val post_service:
    ?description: string ->
    query:'query Query.t ->
    input: 'input Encoding.t ->
    output: 'output Encoding.t ->
    error: 'error Encoding.t ->
    ('prefix, 'params) Path.t ->
    ([ `POST ], 'prefix, 'params, 'query, 'input, 'output, 'error) service

  val delete_service:
    ?description: string ->
    query:'query Query.t ->
    output: 'output Encoding.t ->
    error: 'error Encoding.t ->
    ('prefix, 'params) Path.t ->
    ([ `DELETE ], 'prefix, 'params, 'query, unit, 'output, 'error) service

  val patch_service:
    ?description: string ->
    query:'query Query.t ->
    input: 'input Encoding.t ->
    output: 'output Encoding.t ->
    error: 'error Encoding.t ->
    ('prefix, 'params) Path.t ->
    ([ `PATCH ], 'prefix, 'params, 'query, 'input, 'output, 'error) service

  val put_service:
    ?description: string ->
    query:'query Query.t ->
    input: 'input Encoding.t ->
    output: 'output Encoding.t ->
    error: 'error Encoding.t ->
    ('prefix, 'params) Path.t ->
    ([ `PUT ], 'prefix, 'params, 'query, 'input, 'output, 'error) service

  val prefix:
    ('prefix, 'inner_prefix) Path.t ->
    ('meth, 'inner_prefix, 'params, 'query,
     'input, 'output, 'error) service ->
    ('meth, 'prefix, 'params,
     'query, 'input, 'output, 'error) service

  val map:
    ('a -> 'b) ->
    ('b -> 'a) ->
    ('meth, 'pr, 'a, 'q, 'i, 'o, 'e) service ->
    ('meth, 'pr, 'b, 'q, 'i, 'o, 'e) service

  type ('prefix, 'params) description_service =
    ([ `GET ], 'prefix, 'params * string list, Description.request,
     unit, Encoding.schema Description.directory, unit) service

  val description_service:
    ?description:string ->
    ('prefix, 'params) Path.t ->
    ('prefix, 'params) description_service

  type 'input request = {
    meth: meth ;
    uri: Uri.t ;
    input: 'input input ;
  }

  val forge_request:
    ('meth, unit, 'params, 'query, 'input, 'output, 'error) service ->
    ?base:Uri.t -> 'params -> 'query -> 'input request

  module Internal : sig

    include (module type of (struct include Internal end))

    type ('query, 'input, 'output, 'error) types = {
      query : 'query Query.t ;
      input : 'input input ;
      output : 'output Encoding.t ;
      error : 'error Encoding.t ;
    }

    type (+'meth, 'prefix, 'params, 'query,
          'input, 'output, 'error) iservice = {
      description : string option ;
      meth : 'meth ;
      path : ('prefix, 'params) path ;
      types : ('query, 'input, 'output, 'error) types ;
    } constraint 'meth = [< meth ]

    exception Not_equal
    type (_, _) eq =
      | Eq : (('query, 'input, 'output, 'error) types,
              ('query, 'input, 'output, 'error) types) eq
    val eq :
      ('query1, 'input1, 'output1, 'error1) types ->
      ('query2, 'input2, 'output2, 'error2) types ->
      (('query1, 'input1, 'output1, 'error1) types,
       ('query2, 'input2, 'output2, 'error2) types) eq

    val from_service:
      ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) iservice ->
      ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) service
    val to_service:
      ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) service ->
      ('meth, 'prefix, 'params, 'query, 'input, 'output, 'error) iservice

  end

end
