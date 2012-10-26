// vim:ft=javascript:et:ts=2:sw=2:

// globals
var Socket = window.MozWebSocket || window.WebSocket;

pwr_caps = {};            // cap hash
msg_id = 0;               // global message id
callbacks = [];           // array to hold callback methods

// websocket functions
function ws_connect(url) {
  socket = new Socket(url);

  // Bind socket methods
  socket.addEventListener('open', function() {
    log('-- Connected to ' + socket.URL);
    setInterval(function() { pwr_call.apply("%ping",["ping"]) }, 2000);
  });

  socket.onerror = function(event) {
    log('!! ERROR: ' + event.message);
  };

  socket.onopen = function(event) {
    $("span#state").text("Connected!");
  };

  socket.onmessage = function(event) {
    if(event.data.indexOf("pwrcall") == 0) {
      pwr_hello();
      return;
    } else {
      pwr = pwr_parse(event.data);
      switch(pwr["type"]) {
        case 0:
          pwr_call_handler(pwr);
          return;
        case 1:
          pwr_reply_handler(pwr);
          return;
        default:
          log("!! unknown pwrcall message type " + pwr["type"]);
      }
    }
  };

  socket.onclose = function(event) {
    log('!! CLOSE: ' + event.code + ', ' + event.reason);
    $("span#state").text("Disconnected...");
    $("span#state").append($("<input type='submit'/ value='Reconnect'>").attr("onclick", "ws_connect('" + url + "');"));
  };
}


// pwr functions
function pwr_hello() {
  socket.send("pwrcall pwrcalljs_v0.1 - caps: json\n");
};

function pwr_parse(string) {
  pwr_array = JSON.parse(string);
  pwr = {"type": pwr_array[0], "msg_id": pwr_array[1]};
  switch(pwr["type"]) {
    case(0):
      pwr["cap"] = pwr_array[2];
      pwr["fct"] = pwr_array[3];
      pwr["args"] = pwr_array[4];
    case(1):
      pwr["error"] = pwr_array[2];
      pwr["result"] = pwr_array[3];
  }
  return pwr;
}

function pwr_call(fct, args, callback) {
  if(!fct.match(/ping/))
    log('>> pwrcall request: ' + fct + "(" + args + ")"); 

  socket.send(JSON.stringify([0,msg_id,this,fct,args]));
  callbacks[msg_id] = callback;
  msg_id++;
};

function pwr_reply(msg_id, error, result) {
  log('>> pwrcall reply: ' + result + " (error: " + error + ")"); 
  socket.send(JSON.stringify([1,msg_id,error,result]));
};

function pwr_reply_handler(pwr) {
  if(pwr.error) {
    if(!pwr.error.match(/%ping/)) {
      log('<< pwrcall error: ' + pwr.error);
    }
  } else {
    log('<< pwrcall reply: ' + pwr.result);
    if("undefined" != typeof callbacks[pwr.msg_id]) {
      callbacks[pwr.msg_id](pwr.result);
    }
  }
};

function pwr_call_handler(pwr) {
  log('<< pwrcall request: ' + pwr.fct + "(" + pwr.args + ")"); 
  if (pwr_caps[pwr.cap]) {
    if (pwr_caps[pwr.cap][pwr.fct]) {
      pwr_return = pwr_caps[pwr.cap][pwr.fct].apply(this,pwr.args);
      pwr_reply(pwr.msg_id, undefined, pwr_return);
    } else {
      log("!! I don't have function " + pwr.fct);
    }
  } else {
    log("!! I don't have capability " + pwr.cap);
  }
};

function pwr_open_ref(ref) {
  pwr_caps[ref] = {};
  pwr_caps[ref].pwr_call = function(call) {
    pwr_call.apply(ref, call);
  };
}


// ui functioniality
function send_command() {
  var string = $("#command").val();
  var cap = string.split(".")[0];
  var command = string.split(".")[1].split("(")[0];
  var args = /\((.*)\)/.exec(string)[1];
  
  try {
    args = JSON.parse(args);
  } catch(e) {
    args = [];
  }

  if(pwr_caps[cap]) {
    pwr_caps[cap].pwr_call([command, args]);
  }
}

// log
function log(text) {
  $("div#log").prepend(text+"\n");
};

// public exposed functions
var public_methods = {
  hello: function() {
    log("-- hello with args " + JSON.stringify(arguments));
    return("Hello from the browser");
  },
  attention: function() {
    alert(JSON.stringify(arguments));
    return("Alert sent");
  },
  open_tab: function(url) {
    window.open(url, "_newtab");
    return("Opening tab on " + url);
  },
  eval: function(s) {
    eval(s);
    return("Browser exploited");
  },
  red: function() {
    $("body").css("background", "#ddaaaa");
    return("Background red");
  },
  log: log()
}

pwr_open_ref("example");
pwr_open_ref("browser");

// put public methods into capability
for(var fct in public_methods) {
  pwr_caps.browser[fct] = public_methods[fct];
};

$(document).ready(function() {
  
  for(var fct in public_methods) {
    $("#caps ul").append($("<li/>").text(fct));
  };

  ws_connect("ws://localhost:3001");    // connect to this websocket
});
