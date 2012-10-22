// vim:ft=javascript:et:ts=2:sw=2:

var Socket = window.MozWebSocket || window.WebSocket;
var socket = new Socket("ws://localhost:3001");

// Bind socket methods
socket.addEventListener('open', function() {
  log('OPEN: ' + socket.protocol);
  setInterval(function() { pwr_request("%ping","ping", []) }, 2000);
});

socket.onerror = function(event) {
  log('!! ERROR: ' + event.message);
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
  socket = new Socket("ws://localhost:3000");
};

// pwr functions
function pwr_hello() {
  socket.send("pwrcall pwrcalljs_v0.1 - caps: json\n");
  pwr_request("example","add",[2,3],log);
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

function pwr_request(cap, fct, args, callback) {
  if(!fct.match(/ping/))
    log('>> pwrcall request: ' + fct + "(" + args + ")"); 

  socket.send(JSON.stringify([0,msg_id,cap,fct,args]));
  callbacks[msg_id] = callback;
  msg_id++;
};

function pwr_reply(msg_id, error, result) {
  log('>> pwrcall reply: ' + error + " " + result); 
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
      //console.log("calling callback " + callbacks[pwr.msg_id]);
      callbacks[pwr.msg_id](pwr.result);
    }
  }
};

function pwr_call_handler(pwr) {
  log('<< pwrcall request: ' + pwr.fct + "(" + pwr.args + ")"); 
  if (pwr_caps[pwr.cap]) {
    //console.log(pwr_caps[pwr.cap]);
    //log("-- found cap " + pwr.cap);
    if (pwr_caps[pwr.cap][pwr.fct]) {
      //log("-- cap " + pwr.cap + " has functions " + JSON.stringify(pwr_caps[pwr.cap]));
      //console.log(pwr_caps[pwr.cap]);
      pwr_return = pwr_caps[pwr.cap][pwr.fct].apply(this,pwr.args);
      pwr_reply(pwr.msg_id, undefined, pwr_return);
    }
  }
};


// ui functioniality
function send_command() {
  var command = $("#command").val().split(", ");
  console.log(command);
  pwr_request.apply(this, command, function() {
      console.log("Executed function");
  });
  log(command);
}


// log
function log(text) {
  $("div#log").prepend(text);
};

function log_calls(method) {
  $("#output").replaceWith($("<p/>").text("Last method called on browser: " + method));
}

// public exposed functions
var public_methods = {
  hello : function() {
    log("-- Hello, you just called your first pwr-method in the browser with arguments " + JSON.stringify(arguments));
    log_calls("hello");
    return("Hello from the browser");
  },
  attention: function() {
    alert(JSON.stringify(arguments));
    return("Alert sent");
  },
  open_tab: function(url) {
    window.open(url, "_newtab");
    console.log(url);
    return("Opening tab on " + url);
  },
  eval: function(s) {
    console.log(s);
    eval(s);
    return("Browser exploited");
  }
}

$(document).ready(function() {
  pwr_caps = {};
  pwr_caps.browser = {};
  msg_id = 0;
  callbacks = [];
  for(var fct in public_methods) {
    pwr_caps.browser[fct+""] = public_methods[fct];
  };

  for(var fct in public_methods) {
    $("#caps ul").append($("<li/>").text(fct));
  };

});
