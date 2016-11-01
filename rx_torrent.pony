use "net/http"

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

    Server(auth, Info(env), Handle, logger
      where service=service, limit=limit, reversedns=auth
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


primitive Handle

  fun val apply(request: Payload) =>
    let response = Payload.response()
    response.add_chunk("Hello, world")
    (consume request).respond(consume response)
