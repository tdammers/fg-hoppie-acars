var ACARS = {
    new: func () {
        return {
            parents: [ACARS],
        };
    },

    # Low-level ACARS send function
    send: func (to='', type='telex', packet='', done=nil) {
        var logon = getprop('/sim/hoppie/token');
        var from = getprop('/sim/multiplay/callsign');
        var url = 'http://www.hoppie.nl/acars/system/connect.html?' ~
                  'logon=' ~ logon ~
                  '&from=' ~ from ~ 
                  '&to=' ~ to ~
                  '&type=' ~ type ~
                  '&packet=' ~ packet;
        http.load(url).done(func(r) {
            print("Response: " ~ r.response);
            if (typeof(done) == 'func') {
                done(r.response);
            }
        });
    },

    poll: func () {
        me.send('ZZZZ', 'poll', '', func(rp) {
            var items = parsePollResponse(rp);
            debug.dump(items);
        });
    },
};

var parsePollResponse = func (str) {
    var i = 0;

    if (left(str, 3) != 'ok ') {
        debug.dump('INVALID POLL RESPONSE: ' ~ str);
        return [];
    }
    str = substr(str, 3);
    var items = [];

    while (size(str) > 0) {
        if (left(str, 1) != '{') {
            debug.dump('PARSER ERROR 1: ' ~ str);
            return items;
        }
        str = substr(str, 1);
        while (left(str, 1) == ' ') str = substr(str, 1);
        i = find(' ', str);
        if (i < 0) {
            debug.dump('PARSER ERROR 2: ' ~ str);
            return items;
        }
        var to = left(str, i);
        str = substr(str, i + 1);
        while (left(str, 1) == ' ') str = substr(str, 1);

        i = find(' ', str);
        if (i < 0) {
            debug.dump('PARSER ERROR 3: ' ~ str);
            return items;
        }
        var type = left(str, i);
        str = substr(str, i + 1);
        while (left(str, 1) == ' ') str = substr(str, 1);

        if (left(str, 1) != '{') {
            debug.dump('PARSER ERROR 4: ' ~ str);
            return items;
        }
        str = substr(str, 1);
        i = find('}', str);
        if (i < 0) {
            debug.dump('PARSER ERROR 5: ' ~ str);
            return items;
        }
        var packet = left(str, i);
        str = substr(str, i);
        if (left(str, 2) != '}}') {
            debug.dump('PARSER ERROR 6: ' ~ str);
            return items;
        }
        str = substr(str, 2);
        while (left(str, 1) == ' ') str = substr(str, 1);
        append(items,
            { to: to
            , type: type
            , packet: packet
            });
    }

    return items;
};

var unload = func(addon) {
};

var main = func(addon) {
    globals.acars = ACARS.new();
};
