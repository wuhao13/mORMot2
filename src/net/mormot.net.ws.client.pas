/// WebSockets Client-Side Process 
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.net.ws.client;

{
  *****************************************************************************

    WebSockets Bidirectional Client
    - TWebSocketProcessClient Processing Class
    - THttpClientWebSockets Bidirectional REST Client
    - Socket.IO / Engine.IO Client Protocol over WebSockets

  *****************************************************************************

}

interface

{$I ..\mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.datetime,
  mormot.core.data,
  mormot.core.log,
  mormot.core.threads,
  mormot.core.rtti,
  mormot.core.json,
  mormot.core.buffers,
  mormot.crypt.core,
  mormot.crypt.ecc,
  mormot.crypt.secure, // IProtocol definition
  mormot.net.sock,
  mormot.net.http,
  mormot.net.client,
  mormot.net.server,  // THttpServerRequest for callbacks
  mormot.net.ws.core;



{ ******************** TWebSocketProcessClient Processing Class }

type
  {$M+}
  THttpClientWebSockets = class;

  TWebSocketProcessClientThread = class;
  {$M-}

  /// implements WebSockets process as used on client side
  TWebSocketProcessClient = class(TWebCrtSocketProcess)
  protected
    fClientThread: TWebSocketProcessClientThread;
    fConnectionID: THttpServerConnectionID;
    function ComputeContext(
      out RequestProcess: TOnHttpServerRequest): THttpServerRequestAbstract; override;
  public
    /// initialize the client process for a given THttpClientWebSockets
    constructor Create(aSender: THttpClientWebSockets;
      aConnectionID: THttpServerConnectionID;
      aProtocol: TWebSocketProtocol; const aProcessName: RawUtf8); reintroduce; virtual;
    /// finalize the process
    destructor Destroy; override;
  published
    /// the server-side connection ID, as returned during 101 connection
    // upgrade in 'Sec-WebSocket-Connection-ID' response header
    property ConnectionID: THttpServerConnectionID
      read fConnectionID;
  end;

  /// the current state of the client side processing thread
  TWebSocketProcessClientThreadState = (
    sCreate,
    sRun,
    sFinished,
    sClosed);

  /// WebSockets processing thread used on client side
  // - will handle any incoming callback
  TWebSocketProcessClientThread = class(TSynThread)
  protected
    fThreadState: TWebSocketProcessClientThreadState;
    fProcess: TWebSocketProcessClient;
    procedure Execute; override;
  public
    constructor Create(aProcess: TWebSocketProcessClient); reintroduce;
  end;


{ ******************** THttpClientWebSockets Bidirectional REST Client }

  /// Socket API based REST and HTTP/1.1 client, able to upgrade to WebSockets
  // - will implement regular HTTP/1.1 until WebSocketsUpgrade() is called
  THttpClientWebSockets = class(THttpClientSocket)
  protected
    fProcess: TWebSocketProcessClient;
    fSettings: TWebSocketProcessSettings;
    fOnCallbackRequestProcess: TOnHttpServerRequest;
    fOnBeforeIncomingFrame: TOnWebSocketProtocolIncomingFrame;
    fOnWebSocketsClosed: TNotifyEvent;
    procedure SetReceiveTimeout(aReceiveTimeout: integer); override;
  public
    /// low-level client WebSockets connection factory for host and port
    // - calls Open() then WebSocketsUpgrade() for a given protocol
    // - with error interception and optional logging, returning nil on error
    class function WebSocketsConnect(const aHost, aPort: RawUtf8;
      aProtocol: TWebSocketProtocol; aLog: TSynLogClass = nil;
      const aLogContext: RawUtf8 = ''; const aUri: RawUtf8 = '';
      const aCustomHeaders: RawUtf8 = ''; aTls: boolean = false;
      aTLSContext: PNetTlsContext = nil): THttpClientWebSockets; overload;
    /// low-level client WebSockets connection factory for a given URI
    // - would recognize ws://host:port/uri or wss://host:port/uri (over TLS)
    // - calls Open() then WebSocketsUpgrade() for a given protocol
    // - with error interception and optional logging, returning nil on error
    class function WebSocketsConnect(const aUri: RawUtf8;
      aProtocol: TWebSocketProtocol; aLog: TSynLogClass = nil;
      const aLogContext: RawUtf8 = ''; const aCustomHeaders: RawUtf8 = '';
      aTLSContext: PNetTlsContext = nil): THttpClientWebSockets; overload;
    /// common initialization of all constructors
    // - this overridden method will set the UserAgent with some default value
    constructor Create(aTimeOut: PtrInt = 10000); override;
    /// finalize the connection
    destructor Destroy; override;
    /// process low-level REST request, either on HTTP/1.1 or via WebSockets
    // - after WebSocketsUpgrade() call, will use WebSockets for the communication
    function Request(const url, method: RawUtf8; KeepAlive: cardinal;
      const header: RawUtf8; const Data: RawByteString; const DataType: RawUtf8;
      retry: boolean; InStream: TStream = nil; OutStream: TStream = nil): integer; override;
    /// upgrade the HTTP client connection to a specified WebSockets protocol
    // - i.e. 'synopsebin' and optionally 'synopsejson' modes
    // - you may specify an URI to as expected by the server for upgrade
    // - if aWebSocketsAjax equals default FALSE, it will register the
    // TWebSocketProtocolBinaryprotocol, with AES-CFB 256 bits encryption
    // if the encryption key text is not '' and optional SynLZ compression
    // - if aWebSocketsAjax is TRUE, it will register the slower and less secure
    // TWebSocketProtocolJson (to be used for AJAX debugging/test purposes only)
    // and aWebSocketsEncryptionKey/aWebSocketsCompression parameters won't be used
    // - aWebSocketsEncryptionKey format follows TWebSocketProtocol.SetEncryptKey,
    // so could be e.g. 'password#xxxxxx.private' or 'a=mutual;e=aesctc128;p=34a2..'
    // to use TEcdheProtocol, or a plain password for TProtocolAes
    // - alternatively, you can specify your own custom TWebSocketProtocol
    // instance (owned by this method and immediately released on error)
    // - will return '' on success, or an error message on failure
    function WebSocketsUpgrade(
      const aWebSocketsURI, aWebSocketsEncryptionKey: RawUtf8;
      aWebSocketsAjax: boolean = false;
      aWebSocketsBinaryOptions: TWebSocketProtocolBinaryOptions = [pboSynLzCompress];
      aProtocol: TWebSocketProtocol = nil; const aCustomHeaders: RawUtf8 = ''): RawUtf8;
    /// allow to customize the WebSockets processing
    // - those parameters are accessed by reference to the existing connections
    // so you should better not modify them once the client is upgraded
    function Settings: PWebSocketProcessSettings;
      {$ifdef HASINLINE}inline;{$endif}
    /// this event handler will be executed for any incoming push notification
    property OnCallbackRequestProcess: TOnHttpServerRequest
      read fOnCallbackRequestProcess write fOnCallbackRequestProcess;
    /// event handler trigerred when the WebSocket link is destroyed
    // - may happen e.g. after graceful close from the server side, or
    // after DisconnectAfterInvalidHeartbeatCount is reached
    property OnWebSocketsClosed: TNotifyEvent
      read fOnWebSocketsClosed write fOnWebSocketsClosed;
    /// allow low-level interception before
    // TWebSocketProcessClient.ProcessIncomingFrame is executed
    property OnBeforeIncomingFrame: TOnWebSocketProtocolIncomingFrame
      read fOnBeforeIncomingFrame write fOnBeforeIncomingFrame;
  published
    /// the current WebSockets processing class
    // - equals nil for plain HTTP/1.1 mode
    // - points to the current WebSockets process instance, after a successful
    // WebSocketsUpgrade() call, so that you could use e.g. WebSockets.Protocol
    // to retrieve the protocol currently used
    property WebSockets: TWebSocketProcessClient
      read fProcess;
  end;


function ToText(st: TWebSocketProcessClientThreadState): PShortString; overload;


{ ******************** Socket.IO / Engine.IO Client Protocol over WebSockets }

type
  TSocketIONamespaceClient = class(TSocketIONamespace)
  public
  end;
  TSocketIONamespaceClients = array of TSocketIONamespaceClient;

  /// a HTTP/HTTPS client, able to upgrade to Socket.IO over WebSockets
  // - no polling mode is supported by this class
  TSocketsIOClient = class(TEngineIOAbstract)
  protected
    fClient: THttpClientWebSockets;
    fNameSpace: TSocketIONamespaceClients;
    function GetNameSpace(const aNameSpace: RawUtf8): TSocketIONamespaceClient;
      {$ifdef HASINLINE} inline; {$endif}
    // in-place-decode one Engine.IO OPEN payload on client side
    procedure AfterOpen(OpenPayload: PUtf8Char);
  public
    /// low-level client WebSockets connection factory for host and port
    // - calls Open() then SioUpgrade() for the Socket.IO protocol
    // - with error interception and optional logging, returning nil on error
    class function SioOpen(const aHost, aPort: RawUtf8;
      aLog: TSynLogClass = nil; const aLogContext: RawUtf8 = '';
      const aRoot: RawUtf8 = ''; const aCustomHeaders: RawUtf8 = '';
      aTls: boolean = false; aTLSContext: PNetTlsContext = nil): TSocketsIOClient; overload;
    /// low-level client WebSockets connection factory for host and port
    // - calls Open() then SioUpgrade() for the Socket.IO protocol
    // - with error interception and optional logging, returning nil on error
    // - would recognize ws://host:port/uri or wss://host:port/uri (over TLS)
    // - if no root UI is supplied, default /socket.io/ will be used
    class function SioOpen(const aUri: RawUtf8;
      aLog: TSynLogClass = nil; const aLogContext: RawUtf8 = '';
      const aCustomHeaders: RawUtf8 = '';
      aTls: boolean = false; aTLSContext: PNetTlsContext = nil): TSocketsIOClient; overload;
    /// setup this instance with a connected and upgraded websockets client
    constructor Create(aClient: THttpClientWebSockets); reintroduce;
    /// finalize this instance
    destructor Destroy; override;
    /// return the array of connected namespaces as text
    function NameSpaces: TRawUtf8DynArray;
    /// access to a given Socket.IO namespace
    // - makes a connect if needed
    function Connect(const aNameSpace: RawUtf8): TSocketIONamespaceClient;
    /// raw access to the associated WebSockets connection
    property Client: THttpClientWebSockets
      read fClient;
  end;

  TWebSocketSocketIOClientProtocol = class(TWebSocketSocketIOProtocol)
  protected
    fClient: TSocketsIOClient;
    procedure EnginePacketReceived(Sender: TWebSocketProcess; PacketType: TEngineIOPacket;
      PayLoad: PUtf8Char; PayLoadLen: PtrInt; PayLoadBinary: boolean); override;
    // this is the main entry point for incoming Socket.IO messages
    procedure SocketPacketReceived(Sender: TWebSocketProcess;
      const Message: TSocketIOMessage); override;
  end;


implementation


{ ******************** TWebSocketProcessClient Processing Class }

function ToText(st: TWebSocketProcessClientThreadState): PShortString;
begin
  result := GetEnumName(TypeInfo(TWebSocketProcessClientThreadState), ord(st));
end;


{ TWebSocketProcessClient }

constructor TWebSocketProcessClient.Create(aSender: THttpClientWebSockets;
  aConnectionID: THttpServerConnectionID; aProtocol: TWebSocketProtocol;
  const aProcessName: RawUtf8);
var
  endtix: Int64;
begin
  // https://tools.ietf.org/html/rfc6455#section-10.3
  // client-to-server masking is mandatory (but not from server to client)
  fMaskSentFrames := FRAME_LEN_MASK;
  inherited Create(aSender, aProtocol, nil, @aSender.fSettings, aProcessName);
  // initialize the thread after everything is set (Execute may be instant)
  fConnectionID := aConnectionID;
  fClientThread := TWebSocketProcessClientThread.Create(self);
  endtix := GetTickCount64 + 5000;
  repeat // wait for TWebSocketProcess.ProcessLoop to initiate
    SleepHiRes(0);
  until fProcessEnded or
        (fState <> wpsCreate) or
        (GetTickCount64 > endtix);
end;

destructor TWebSocketProcessClient.Destroy;
var
  tix: Int64;
  {%H-}log: ISynLog;
begin
  log := WebSocketLog.Enter('Destroy: ThreadState=%',
    [ToText(fClientThread.fThreadState)^], self);
  try
    // focConnectionClose would be handled in this thread -> close client thread
    fClientThread.Terminate;
    tix := GetTickCount64 + 7000; // never wait forever
    while (fClientThread.fThreadState = sRun) and
          (GetTickCount64 < tix) do
      SleepHiRes(1);
    fClientThread.fProcess := nil;
  finally
    // SendPendingOutgoingFrames + SendFrame/GetFrame(focConnectionClose)
    inherited Destroy;
    fClientThread.Free;
  end;
end;

function TWebSocketProcessClient.ComputeContext(
  out RequestProcess: TOnHttpServerRequest): THttpServerRequestAbstract;
var
  ws: THttpClientWebSockets;
begin
  ws := fSocket as THttpClientWebSockets;
  RequestProcess := ws.fOnCallbackRequestProcess;
  if Assigned(RequestProcess) then
    result := THttpServerRequest.Create(
      nil, 0, fOwnerThread, 0, ws.fProcess.Protocol.ConnectionFlags, nil)
  else
    result := nil;
end;


{ TWebSocketProcessClientThread }

constructor TWebSocketProcessClientThread.Create(aProcess: TWebSocketProcessClient);
begin
  fProcess := aProcess;
  fProcess.fOwnerThread := self;
  inherited Create({suspended=}false);
end;

procedure TWebSocketProcessClientThread.Execute;
begin
  try
    fThreadState := sRun;
    if fProcess <> nil then // may happen when debugging under FPC (alf)
      SetCurrentThreadName(
        '% % %', [fProcess.fProcessName, self, fProcess.Protocol.Name]);
    WebSocketLog.Add.Log(
      sllDebug, 'Execute: before ProcessLoop %', [fProcess], self);
    if not Terminated and
       (fProcess <> nil) then
      fProcess.ProcessLoop;
    WebSocketLog.Add.Log(
      sllDebug, 'Execute: after ProcessLoop %', [fProcess], self);
    if (fProcess <> nil) and
       (fProcess.Socket <> nil) and
       fProcess.Socket.InheritsFrom(THttpClientWebSockets) then
      with THttpClientWebSockets(fProcess.Socket) do
        if Assigned(OnWebSocketsClosed) then
          OnWebSocketsClosed(self);
  except // ignore any exception in the thread
  end;
  fThreadState := sFinished; // safely set final state
  if (fProcess <> nil) and
     (fProcess.fState = wpsClose) then
    fThreadState := sClosed;
  WebSocketLog.Add.Log(sllDebug, 'Execute: done (%)', [ToText(fThreadState)^], self);
end;


{ ******************** THttpClientWebSockets Bidirectional REST Client }

{ THttpClientWebSockets }

constructor THttpClientWebSockets.Create(aTimeOut: PtrInt);
begin
  inherited;
  fSettings.SetDefaults;
  fSettings.CallbackAnswerTimeOutMS := aTimeOut;
end;

class function THttpClientWebSockets.WebSocketsConnect(
  const aHost, aPort: RawUtf8; aProtocol: TWebSocketProtocol; aLog: TSynLogClass;
  const aLogContext, aUri, aCustomHeaders: RawUtf8;
  aTls: boolean; aTLSContext: PNetTlsContext): THttpClientWebSockets;
var
  error: RawUtf8;
begin
  result := nil;
  if (aProtocol = nil) or
     (aHost = '') then
    EWebSockets.RaiseUtf8('%.WebSocketsConnect(nil)', [self]);
  try
    // call socket constructor
    result := Open(aHost, aPort, nlTcp, 10000, aTls, aTLSContext);
    error := result.WebSocketsUpgrade(
      aUri, '', false, [], aProtocol, aCustomHeaders);
    if error <> '' then
      FreeAndNil(result);
    if Assigned(aLog) then
      result.OnLog := aLog.DoLog;
  except
    on E: Exception do
    begin
      aProtocol.Free; // as done in WebSocketsUpgrade()
      FreeAndNil(result);
      FormatUtf8('% %', [E, E.Message], error);
    end;
  end;
  if aLog <> nil then
    if result <> nil then
      aLog.Add.Log(sllDebug, '%: WebSocketsConnect %', [aLogContext, result])
    else
      aLog.Add.Log(sllWarning, '%: WebSocketsConnect %:% failed - %',
        [aLogContext, aHost, aPort, error]);
end;

class function THttpClientWebSockets.WebSocketsConnect(const aUri: RawUtf8;
  aProtocol: TWebSocketProtocol; aLog: TSynLogClass;
  const aLogContext, aCustomHeaders: RawUtf8;
  aTLSContext: PNetTlsContext): THttpClientWebSockets;
var
  uri: TUri;
begin
  if (aProtocol = nil) or
     not uri.From(aUri) then
    EWebSockets.RaiseUtf8('%.WebSocketsConnect(nil)', [self]);
  result := WebSocketsConnect(uri.Server, uri.Port, aProtocol,
    aLog, aLogContext, uri.Address, aCustomHeaders, uri.Https, aTLSContext);
end;

destructor THttpClientWebSockets.Destroy;
begin
  FreeAndNil(fProcess);
  inherited;
end;

function THttpClientWebSockets.Request(const url, method: RawUtf8;
  KeepAlive: cardinal; const header: RawUtf8; const Data: RawByteString;
  const DataType: RawUtf8; retry: boolean; InStream, OutStream: TStream): integer;
var
  Ctxt: THttpServerRequest;
  block: TWebSocketProcessNotifyCallback;
  body, resthead: RawUtf8;
begin
  if fProcess <> nil then
  begin
    if fProcess.fClientThread.fThreadState = sCreate then
      sleep(10); // paranoid warmup of TWebSocketProcessClientThread.Execute
    if fProcess.fClientThread.fThreadState <> sRun then
      // WebSockets closed by server side: notify client-side error
      result := HTTP_CLIENTERROR
    else
    begin
      // send the REST request over WebSockets - both ends use NotifyCallback()
      Ctxt := THttpServerRequest.Create(nil, fProcess.Protocol.ConnectionID,
        fProcess.fOwnerThread, 0, fProcess.Protocol.ConnectionFlags,
        fProcess.Protocol.ConnectionOpaque);
      try
        body := Data;
        if InStream <> nil then
          body := body + StreamToRawByteString(InStream);
        Ctxt.PrepareDirect(url, method, header, body, DataType, '');
        FindNameValue(header, 'SEC-WEBSOCKET-REST:', resthead);
        if resthead = 'NonBlocking' then
          block := wscNonBlockWithoutAnswer
        else
          block := wscBlockWithAnswer;
        result := fProcess.NotifyCallback(Ctxt, block);
        if IdemPChar(pointer(Ctxt.OutContentType), JSON_CONTENT_TYPE_UPPER) then
          HeaderSetText(Ctxt.OutCustomHeaders)
        else
          HeaderSetText(Ctxt.OutCustomHeaders, Ctxt.OutContentType);
        Http.ContentLength := length(Ctxt.OutContent);
        if OutStream <> nil then
          OutStream.WriteBuffer(pointer(Ctxt.OutContent)^, Http.ContentLength)
        else
          Http.Content := Ctxt.OutContent;
        Http.ContentType := Ctxt.OutContentType;
      finally
        Ctxt.Free;
      end;
    end;
  end
  else
    // standard HTTP/1.1 REST request (before WebSocketsUpgrade call)
    result := inherited Request(url, method, KeepAlive, header, Data, DataType,
      retry, InStream, OutStream);
end;

procedure THttpClientWebSockets.SetReceiveTimeout(aReceiveTimeout: integer);
begin
  inherited SetReceiveTimeout(aReceiveTimeout);
  fSettings.CallbackAnswerTimeOutMS := aReceiveTimeout;
end;

function THttpClientWebSockets.Settings: PWebSocketProcessSettings;
begin
  result := @fSettings;
end;

{$ifdef ISDELPHI20062007}
  {$warnings off} // avoid paranoid Delphi 2007 warning
{$endif ISDELPHI20062007}

function THttpClientWebSockets.WebSocketsUpgrade(
  const aWebSocketsURI, aWebSocketsEncryptionKey: RawUtf8;
  aWebSocketsAjax: boolean;
  aWebSocketsBinaryOptions: TWebSocketProtocolBinaryOptions;
  aProtocol: TWebSocketProtocol; const aCustomHeaders: RawUtf8): RawUtf8;
var
  key: TAESBlock;
  bin1, bin2: RawByteString;
  extin, extout, prot: RawUtf8;
  extins: TRawUtf8DynArray;
  cmd: RawUtf8;
  digest1, digest2: TSha1Digest;
begin
  try
    if fProcess <> nil then
    begin
      result := 'Already upgraded to WebSockets';
      if PropNameEquals(fProcess.Protocol.Uri, aWebSocketsURI) then
        result := result + ' on this URI'
      else
        result := FormatUtf8('% with URI=[%] but requested [%]',
          [result, fProcess.Protocol.Uri, aWebSocketsURI]);
      exit;
    end;
    try
      // setup the new protocol instance
      if aProtocol = nil then
        if aWebSocketsAjax then
          aProtocol := TWebSocketProtocolJson.Create(aWebSocketsURI)
        else
          aProtocol := TWebSocketProtocolBinary.Create(aWebSocketsURI, false,
            aWebSocketsEncryptionKey, @fSettings, aWebSocketsBinaryOptions);
      aProtocol.OnBeforeIncomingFrame := fOnBeforeIncomingFrame;
      // send initial upgrade request
      RequestSendHeader(aWebSocketsURI, 'GET');
      RandomBytes(@key, SizeOf(key)); // Lecuyer is enough for public random
      bin1 := BinToBase64(@key, SizeOf(key));
      SockSend(['Content-Length: 0'#13#10 +
                'Connection: Upgrade'#13#10 +
                'Upgrade: websocket'#13#10 +
                'Sec-WebSocket-Key: ', bin1, #13#10 +
                'Sec-WebSocket-Protocol: ', aProtocol.GetSubprotocols, #13#10 +
                'Sec-WebSocket-Version: 13']);
      if aProtocol.ProcessHandshake(nil, extout, nil) and
         (extout <> '') then
        SockSend(['Sec-WebSocket-Extensions: ', extout]); // e.g. TEcdheProtocol
      if aCustomHeaders <> '' then
        SockSend(aCustomHeaders);
      SockSendCRLF;
      SockSendFlush('');
      // validate the response as WebSockets upgrade
      SockRecvLn(cmd);
      GetHeader(false);
      if not IdemPChar(pointer(cmd), 'HTTP/1.1 101') then
      begin
        result := cmd;
        if result = '' then
          result := 'No server response';
        exit; // return the unexpected command line as error message
      end;
      prot := HeaderGetValue('SEC-WEBSOCKET-PROTOCOL');
      result := 'Invalid HTTP Upgrade Header';
      if not (hfConnectionUpgrade in Http.HeaderFlags) or
         (Http.ContentLength > 0) or
         not PropNameEquals(Http.Upgrade, 'websocket') or
         not aProtocol.SetSubprotocol(prot) then
        exit;
      aProtocol.Name := prot;
      result := 'Invalid HTTP Upgrade Accept Challenge';
      ComputeChallenge(bin1, digest1);
      bin2 := HeaderGetValue('SEC-WEBSOCKET-ACCEPT');
      if not Base64ToBin(pointer(bin2), @digest2, length(bin2), SizeOf(digest2)) or
         not IsEqual(digest1, digest2) then
        exit;
      if extout <> '' then
      begin
        // process protocol extension (e.g. TEcdheProtocol handshake)
        result := 'Invalid HTTP Upgrade ProcessHandshake';
        extin := HeaderGetValue('SEC-WEBSOCKET-EXTENSIONS');
        CsvToRawUtf8DynArray(pointer(extin), extins, ';', true);
        if (extins = nil) or
           not aProtocol.ProcessHandshake(extins, extout, @result) then
          exit;
      end;
      // if we reached here, connection is successfully upgraded to WebSockets
      if (Server = 'localhost') or
         (Server = '127.0.0.1') then
      begin
        aProtocol.RemoteIP := '127.0.0.1';
        aProtocol.RemoteLocalhost := true;
      end
      else
        aProtocol.RemoteIP := Server;
      result := ''; // no error message = success
      fProcess := TWebSocketProcessClient.Create(self,
        GetInt64(pointer(HeaderGetValue('SEC-WEBSOCKET-CONNECTION-ID'))),
        aProtocol, fProcessName);
      aProtocol := nil; // protocol instance is owned by fProcess now
    except
      on E: Exception do
      begin
        FreeAndNil(fProcess);
        FormatUtf8('%: %', [E, E.Message], result);
      end;
    end;
  finally
    aProtocol.Free;
  end;
end;

{$ifdef ISDELPHI20062007}
  {$warnings on}
{$endif ISDELPHI20062007}


{ ******************** Socket.IO / Engine.IO Client Protocol over WebSockets }


{ TSocketsIOClient }

class function TSocketsIOClient.SioOpen(const aHost, aPort: RawUtf8;
  aLog: TSynLogClass; const aLogContext, aRoot, aCustomHeaders: RawUtf8;
  aTls: boolean; aTLSContext: PNetTlsContext): TSocketsIOClient;
var
  c: THttpClientWebSockets;
begin
  c := THttpClientWebSockets.WebSocketsConnect(aHost, aPort,
    TWebSocketSocketIOClientProtocol.Create('Socket.IO', ''), aLog, aLogContext,
    SocketIOHandshakeUri(aRoot), aCustomHeaders, aTls, aTLSContext);
  if c = nil then
    result := nil
  else
    result := TSocketsIOClient.Create(c);
end;

class function TSocketsIOClient.SioOpen(const aUri: RawUtf8;
  aLog: TSynLogClass; const aLogContext, aCustomHeaders: RawUtf8;
  aTls: boolean; aTLSContext: PNetTlsContext): TSocketsIOClient;
var
  uri: TUri;
begin
  if uri.From(aUri) then // detect both https:// and wss:// schemes
    result := SioOpen(uri.Server, uri.Port, aLog, aLogContext, uri.Address,
      aCustomHeaders, aTls, aTLSContext)
  else
    result := nil;
end;

constructor TSocketsIOClient.Create(aClient: THttpClientWebSockets);
begin
  if (aClient = nil) or
     (aClient.WebSockets = nil) then
    ESocketIO.RaiseUtf8('Unexpected %.Create with no WebSockets', [self]);
  inherited Create;
  fClient := aClient;
  (fClient.WebSockets.Protocol as TWebSocketSocketIOClientProtocol).fClient := self;
end;

destructor TSocketsIOClient.Destroy;
begin
  ObjArrayClear(fNameSpace);
  fClient.Free;
  inherited Destroy;
end;

procedure TSocketsIOClient.AfterOpen(OpenPayload: PUtf8Char);
var
  V: array[0..4] of TValuePUtf8Char;
begin
  JsonDecode(OpenPayload,
    ['sid', 'upgrades', 'pingInterval', 'pingTimeout', 'maxPayload'], @V);
  if V[0].Text = nil then
    EEngineIO.RaiseUtf8('%.Create: missing "sid" in %', [self, OpenPayload]);
  V[0].ToUtf8(fEngineSid);
  if V[1].Text <> nil then
    EEngineIO.RaiseUtf8('%.Create: unsupported "upgrades" in %', [self, OpenPayload]);
  fPingInterval := V[2].ToCardinal(fPingInterval);
  fPingTimeout  := V[3].ToCardinal(fPingTimeout);
  fMaxPayload   := V[4].ToCardinal;
end;

function TSocketsIOClient.GetNameSpace(const aNameSpace: RawUtf8): TSocketIONamespaceClient;
begin
  result := SocketIOGetNameSpace(pointer(fNameSpace), length(fNameSpace),
    pointer(aNameSpace), length(aNameSpace)) as TSocketIONamespaceClient;
end;

function TSocketsIOClient.NameSpaces: TRawUtf8DynArray;
begin
  if fNameSpaces = nil then
    fNameSpaces := SocketIOGetNameSpaces(pointer(fNameSpace), length(fNameSpace));
  result := fNameSpaces;
end;

function TSocketsIOClient.Connect(const aNameSpace: RawUtf8): TSocketIONamespaceClient;
begin
  result := GetNameSpace(aNameSpace);
  if result <> nil then
    exit;
  fNameSpaces := nil; // to be reallocated on need

end;


{ TWebSocketEngineIOClientProtocol }

procedure TWebSocketSocketIOClientProtocol.EnginePacketReceived(
  Sender: TWebSocketProcess; PacketType: TEngineIOPacket;
  PayLoad: PUtf8Char; PayLoadLen: PtrInt; PayLoadBinary: boolean);
var
  msg: TSocketIOMessage;
begin
  if fClient = nil then
    ESocketIO.RaiseUtf8('Unexpected %.EnginePacketReceived', [self]);
  case PacketType of
    eioOpen:
      fClient.AfterOpen(PayLoad);
    eioMessage:
      if msg.Init(PayLoad, PayLoadLen, PayLoadBinary) then
        SocketPacketReceived(Sender, msg)
      else
        ESocketIO.RaiseUtf8('%.EnginePacketReceived: invalid Payload', [self]);
  end;
end;

procedure TWebSocketSocketIOClientProtocol.SocketPacketReceived(
  Sender: TWebSocketProcess; const Message: TSocketIOMessage);
begin

end;


end.

