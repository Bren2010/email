// Generated by CoffeeScript 1.6.3
(function() {
  window.encrypt = function(form) {
    var i, inputs, sum, _i, _ref, _results;
    inputs = form.getElementsByTagName('input');
    _results = [];
    for (i = _i = 0, _ref = inputs.length; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
      if (inputs[i].type === 'password') {
        sum = sjcl.codec.hex.fromBits(sjcl.hash.sha256.hash(inputs[i].value));
        _results.push(inputs[i].value = sum);
      } else {
        _results.push(void 0);
      }
    }
    return _results;
  };

}).call(this);
