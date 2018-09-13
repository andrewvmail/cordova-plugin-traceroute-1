var exec = require('cordova/exec');

exports.startTrace = function(host, success, error) {
  exec(success, error, "CDVTraceRT", "startTrace", [host, 30]);
};

exports.startTraceWithHops = function(host, maxTtl, success, error) {
  exec(success, error, "CDVTraceRT", "startTrace", [host, maxTtl]);
};
