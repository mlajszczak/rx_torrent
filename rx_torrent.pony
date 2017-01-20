use "net/http"
use "itertools"
use "json"
use "files"
use "debug"
use "promises"
use "collections"
use "pony_bencode"

actor Main
  new create(env: Env) =>
    let service = try env.args(1) else "50000" end
    let limit = try env.args(2).usize() else 100 end

    let logger = DiscardLog

    let auth = try
      env.root as AmbientAuth
    else
      env.out.print("unable to use network")
      return
    end

    let keepers = TorrentRegistrar

    Server(auth, Info(env), Handle(auth, keepers), logger
      where host="127.0.0.1", service=service, limit=limit, reversedns=auth
    )


actor TorrentKeeper

actor TorrentRegistrar
  embed _registry: Map[String, TorrentKeeper tag] = _registry.create()

  fun tag update(info_hash: String, value: TorrentKeeper): Promise[None] =>
    let promise = Promise[None]
    _add(info_hash, value, promise)
    promise

  fun tag remove(info_hash: String): Promise[None] =>
    let promise = Promise[None]
    _remove(info_hash, promise)
    promise

  fun tag apply(info_hash: String): Promise[TorrentKeeper] =>
    let promise = Promise[TorrentKeeper]
    _fetch(info_hash, promise)
    promise

  be _add(info_hash: String, torrent: TorrentKeeper, promise: Promise[None]) =>
    if _registry.contains(info_hash) then
      promise.reject()
    else
      _registry(info_hash) = torrent
      promise(None)
    end

  be _remove(info_hash: String, promise: Promise[None]) =>
    try
      _registry.remove(info_hash)
      promise(None)
    else
      promise.reject()
    end

  be _fetch(info_hash: String, promise: Promise[TorrentKeeper]) =>
    try
      promise(_registry(info_hash))
    else
      promise.reject()
    end


class Info
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref listening(server: Server ref) =>
    try
      (let host, let service) = server.local_address().name()
      _env.out.print("Listening on " + host + ":" + service)
    else
      _env.out.print("Couldn't get local address.")
      server.dispose()
    end

  fun ref not_listening(server: Server ref) =>
    _env.out.print("Failed to listen.")

  fun ref closed(server: Server ref) =>
    _env.out.print("Shutdown.")


type StringTuple is (String, String)


class Handle
  let _auth: AmbientAuth
  let _keepers: TorrentRegistrar

  new val create(auth: AmbientAuth, keepers: TorrentRegistrar) =>
    _auth = auth
    _keepers = keepers

  fun val apply(request: Payload) =>
    let path = request.url.path
    let query = try _parse_query(request.url.query) end

    match query
    | let query': Iter[StringTuple] =>
      if path == "/add" then
        _handle_add_torrent(consume request, query')
      elseif path == "/remove" then
        _handle_remove_torrent(consume request, query')
      else
        _handle_invalid_request(consume request)
      end
    else
      _handle_invalid_request(consume request)
    end

    fun val _parse_query(query: String): Iter[StringTuple] ? =>
      Iter[String](URLEncode.decode(query).split("&").values())
        .map[StringTuple]({
          (entry: String): StringTuple ? =>
            let entryArray = entry.split("=")
            (entryArray(0), entryArray(1))
        })

    fun val _handle_add_torrent(request: Payload, query: Iter[StringTuple]) =>

      let torrent_path = try query.find(
        {(entry: StringTuple): Bool => entry._1 == "torrentPath"})
      end

      var response = Payload.response()
      //response.update("Access-Control-Allow-Origin", "*")

      match torrent_path
      | (_, let path: String) =>
        try
          let caps: FileCaps val = recover
            FileCaps.>all().>remove(FileCaps.add(FileCreate))
          end
          let json: JsonDoc val = BencodeDoc
            .>parse_file(FilePath(_auth, path, caps))
            .to_json()
          response.add_chunk(json.string())
        else
          response.add_chunk("{\"error\": \"bad torrent file\"}")
        end
      else
        response.add_chunk("{\"error\": \"bad query\"}")
      end

      (consume request).respond(consume response)

    fun val _handle_remove_torrent(request: Payload, query: Iter[StringTuple]) =>
      None

    fun val _handle_invalid_request(request: Payload) =>
      None
