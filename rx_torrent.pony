use "net/http"
use "itertools"
use "json"
use "files"
use "debug"
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

    Server(auth, Info(env), Handle(auth), logger
      where host="127.0.0.1", service=service, limit=limit, reversedns=auth
    )


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

  new val create(auth: AmbientAuth) =>
    _auth = auth

  fun val apply(request: Payload) =>
    let query = try
      URLEncode.decode(request.url.query)
    else
      ""
    end
    let torrentPath = try Iter[String](query.split("&").values())
      .map[StringTuple]({
        (entry: String): StringTuple =>
          let entryArray = entry.split("=")
          try
            (entryArray(0), entryArray(1))
          else
            ("", "")
          end
      })
      .find({(entry: StringTuple): Bool => entry._1 == "torrentPath"})
    end

    var response = Payload.response()
    response.update("Access-Control-Allow-Origin", "*")

    match torrentPath
    | (_, let path: String) =>
      try
        let caps: FileCaps val = recover
          FileCaps.all().remove(FileCaps.add(FileCreate))
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
