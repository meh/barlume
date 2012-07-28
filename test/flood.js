var net   = require('net');

var created  = 255,
    answered = 0,
    errored  = 0,
    time     = +new Date;


function createClient() {
  var socket = net.createConnection(1337, '127.0.0.1');
  socket.setEncoding('utf8');
  socket
    .on('connect', function() { socket.write('lol'); })
    .on('data', function(c) {
      errored += c !== 'lol' ? 1 : 0;
      if(++answered === created) {
        var t = +new Date - time;
        console.log('Time (ms): ' + t);
        console.log('Errored: ' + errored);
        process.exit();
      }
    });
}

for(var i=0; i <= created; i++) {
  createClient(); 
}

