// vim:ft=javascript:et:ts=2:sw=2:

// globals
var Socket = window.MozWebSocket || window.WebSocket;

var pwr_ns = function() {
  this.caps = {};
  this.callbacks = [];
  this.msg_id = 0;

  // pwr. functions {{{
  this.add_cap = function(cap, host) {
    if(!this.caps[cap]) {
      this.caps[cap] = new this.pwr_cap(cap,host);
    }
  }

  this.handle_reply = function (reply) {
    if(reply.error) {
      if(!reply.error.match(/%ping/)) {
        log('<< pwrcall error: ' + reply.error);
      }
    } else {
      log('<< pwrcall reply: ' + reply.result);
      if("undefined" != typeof this.callbacks[reply.msg_id]) {
        this.callbacks[reply.msg_id](reply.result);
      }
    }
  };

  this.hello = function(socket) {
      socket.send("pwrcall pwrcalljs_v0.1 - caps: json\n");
  };

  this.parse = function(string) {
    var pwr_array = JSON.parse(string);
    var pwr_msg = {"type": pwr_array[0], "msg_id": pwr_array[1]};
    switch(pwr_msg["type"]) {
      case(0):
        pwr_msg["cap"] = pwr_array[2];
        pwr_msg["fct"] = pwr_array[3];
        pwr_msg["args"] = pwr_array[4];
      case(1):
        pwr_msg["error"] = pwr_array[2];
        pwr_msg["result"] = pwr_array[3];
    }
    return pwr_msg;
  }
  // }}}

  // {{{ pwr_cap
  this.pwr_cap = function(cap, host) {
    this.cap = cap;
    this.ws = new pwrsock(host);

    this.pcall = function (fct, args, callback) {
      if(!fct.match(/ping/))
        log('>> pwrcall request: ' + fct + "(" + args + ")"); 

      this.ws.socket.send(JSON.stringify([0,pwr.msg_id,this.cap,fct,args]));
      pwr.callbacks[pwr.msg_id] = callback;
      pwr.msg_id++;
    };

    this.reply = function (msg_id, error, result) {
      log('>> pwrcall reply: ' + result + " (error: " + error + ")"); 
      this.ws.socket.send(JSON.stringify([1,msg_id,error,result]));
    };

    this.handle_call = function (msg) {
      log('<< msgcall request: ' + msg.fct + "(" + msg.args + ")"); 
        if (this[msg.fct]) {
          msg_return = this[msg.fct].apply(this,msg.args);
          this.reply(msg["msg_id"], undefined, msg_return);
        } else {
          log("!! I don't have function " + msg.fct);
        }
    };
  }
  //}}}
};

var pwr = new pwr_ns();

// websocket functions {{{
var pwrsock = function(url) {

  // look if another cap has the same WS
  for(var cap in pwr.caps) {
    if(pwr.caps[cap] && pwr.caps[cap].ws && (pwr.caps[cap].ws.socket.URL == url)) {
      this.socket = pwr.caps[cap].ws.socket;
      break;
    }
  }

  if(!this.socket) {
    this.socket = new Socket(url);

    this.socket.addEventListener('open', function() {
      log('-- Connected to ' + this.URL);
      var s = this;
      setInterval(function() { s.send(JSON.stringify([0, 1, "%ping",["ping"]])) }, 2000);
    });

    this.socket.onerror = function(event) {
      log('!! ERROR: ' + event.message);
    };

    this.socket.onopen = function(event) {
      $("span#state").text("Connected!");
    };

    this.socket.onmessage = function(event) {
      if(event.data.indexOf("pwrcall") == 0) {
        pwr.hello(this);
        return;
      }

      var msg = pwr.parse(event.data);
      switch(msg["type"]) {
        case 0:
          var cap = pwr.caps[msg["cap"]];
          cap.handle_call(msg);
          return;
        case 1:
          pwr.handle_reply(msg);
          return;
        default:
          log("!! unknown pwrcall message type " + msg["type"]);
      }
    };

    this.socket.onclose = function(event) {
      log('!! CLOSE: ' + event.code + ', ' + event.reason);
      $("span#state").text("Disconnected...");
      $("span#state").append($("<input type='submit'/ value='Reconnect'>").attr("onclick", "ws_connect('" + url + "');"));
    };
  }

}

// }}}

// ui functioniality {{{
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

  if(pwr.caps[cap]) {
    pwr.caps[cap].pcall(command, args);
  }
}
//}}}

// log// {{{
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

$(document).ready(function() {
  
  for(var fct in public_methods) {
    $("#caps ul").append($("<li/>").text(fct));
  };

  pwr.add_cap("example", "ws://localhost:3001/");
  pwr.add_cap("browser", "ws://localhost:3001/");

  // put public methods into browser capability
  for(var fct in public_methods) {
    pwr.caps.browser[fct] = public_methods[fct];
  };


});
//}}}
