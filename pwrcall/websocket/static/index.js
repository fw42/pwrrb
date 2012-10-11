var logger = document.getElementsByTagName('ul')[0];
var Socket = window.MozWebSocket || window.WebSocket;
var socket = new Socket('ws://' + location.hostname + ':' + location.port + '/');

function log(text) {
  logger.innerHTML += '<li>' + text + '</li>';
};

socket.addEventListener('open', function() {
  log('OPEN: ' + socket.protocol);
});

socket.onerror = function(event) {
  log('ERROR: ' + event.message);
};

socket.onmessage = function(event) {
  log('MESSAGE: ' + event.data);
};

socket.onclose = function(event) {
  log('CLOSE: ' + event.code + ', ' + event.reason);
};
