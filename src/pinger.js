'use strict';

const pinger = require('tcp-ping');

function handler(event, context, callback) {
  // Event should be an object which may have these properties:
  // address (localhost)
  // port (80)
  // timeout (5s), in ms
  // attempts (10)

  pinger.ping(event, (error, data) => {
    if (error) {
      console.log(`Error pinging: ${error}`);
      return callback(error);
    }
    console.log(JSON.stringify(data));
    return callback(null, 'Successful ping.');
  });
}

module.exports = {
  handler,
};
