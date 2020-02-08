-module(forwarder).

-export([start_link/0,start/0,stop/0]).
-export([init/0]).
-export([send_message/1]).

%% Management API.

start() ->
    proc_lib:start(?MODULE, init, []).

start_link() ->
    proc_lib:start_link(?MODULE, init, []).

stop() ->
    cast(stop).

%% Server state.

-record(state, {}).

%% User API.

send_message(Message) ->
    cast({send_message,Message}).

%% Internal protocol functions.

cast(Message) ->
    sub_server ! {cast,self(),Message},
    ok.

%% Initialise it all.

init() ->
    {ok, Socket} = chumak:socket(sub),
    %% List of topics, put them in a list or something.
    Heartbeat = <<"heartbeat">>,
    TorchUp = <<"torch-up">>,
    Telecom = <<"telecom">>,
    Datacom = <<"datacom">>,
    Logging = <<"logging">>,
    %% ZeroMQ subscribe socket and topics!
    chumak:subscribe(Socket, Heartbeat),
    chumak:subscribe(Socket, TorchUp),
    chumak:subscribe(Socket, Telecom),
    chumak:subscribe(Socket, Datacom),
    chumak:subscribe(Socket, Logging),
    %% subscribe spaceboard config
    econfig:subscribe(spaceboard),
    Port = econfig:get_integer(spaceboard, "zmq", "sub_bind"),
    Address = econfig:get_value(spaceboard, "zmq", "address"),
    %% ZeroMQ bind this for me please.
    case chumak:bind(Socket, tcp, Address, Port) of
        {ok, _BindPid} ->
            io:format("Binding OK with Pid: ~p\n", [Socket]);
        {error, Reason} ->
            io:format("Connection Failed for this reason: ~p\n", [Reason]);
        X ->
            io:format("Unhandled reply for bind ~p \n", [X])
    end,
    %% Spawn BEAM process that handle the messaging loop
    spawn_link(fun () ->
            zmq_loop(Socket)
    end),
    register(sub_server, self()),
    proc_lib:init_ack({ok,self()}),
    loop(#state{}).

zmq_loop(Socket) ->
    {ok, Data1} = chumak:recv(Socket),
    process_pub(binary:split(Data1, [<<" ">>], [])),
    zmq_loop(Socket).

loop(State) ->
    receive
        {cast,From,{send_message,Message}} ->
            io:format("~w: ~p\n", [From,Message]),
            loop(State);
        % We're done
        {cast,_From,stop} ->
            ok;
        % Ignore everything else
        _ ->
            loop(State)
    end.

process_pub([H|T]) ->
    logger:warning("A head just spawn in here ~p \n", [H]),
    Payload = jiffy:decode([T], [return_maps]),
    
    logger:warning(maps:get(<<"timestamp">>, Payload, "0000000000")),
    logger:warning(maps:get(<<"uuid">>, Payload, uuid:uuid_to_string(uuid:get_v4()))).

    %%case binary:split(Stuff, [<<" ">>], []) of
    %%    [<<"heartbeat">>, _] -> logger:error(_);
    %%    [<<"">>, _] -> logger:error("wut")
    %%end.

    %%http_client(),    D= ???

http_client() ->
    %% currently testing both hackney and gun!
    URL = <<"https://api.torchup.net">>,
    %% setting things up
    Headers = [],
    Payload = <<>>,
    Options = [],
    %% request response
    {ok, StatusCode, RespHeaders, ClientRef} = hackney:get(URL, Headers, Payload, Options),
    %% where are you?
    logger:warning("rarely? ~p \n", [StatusCode]).
