var ACARS = {
    new: func () {
        return {
            parents: [ACARS],
            downlinkNode: props.globals.getNode('/acars/downlink', 1),
            pollTimer: nil,
        };
    },

    start: func () {
        print("ACARS start");
        if (me.pollTimer == nil) {
            me.pollTimer = maketimer(5, me, me.poll);
            me.pollTimer.simulatedTime = 1;
            me.pollTimer.singleShot = 0;
        }
        if (!me.pollTimer.isRunning) {
            me.pollTimer.start();
        }
    },

    stop: func () {
        print("ACARS stop");
        if (me.pollTimer != nil) {
            me.pollTimer.stop();
        }
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
            foreach (var item; items) {
                me.processResponse(item);
            }
        });
    },

    downlink: func(type, from, text) {
        var msgNode = me.downlinkNode.addChild('message');
        msgNode.setValue('type', type);
        msgNode.setValue('from', from);
        msgNode.setValue('text', text);
        msgNode.setValue('status', 'new');
        var formattedNode = me.downlinkNode.getNode('formatted');
        formattedNode.setValue(formattedNode.getValue() ~ "\n---\n" ~
            sprintf("%s %s\n%s", from, type, text));
    },

    processResponse: func(item) {
        if (item.type == 'telex') {
            me.downlink('telex', item.from, item.packet);
        }
        else {
            debug.dump('Ignoring response item', item);
        }
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
        var from = left(str, i);
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
            { from: from
            , type: type
            , packet: packet
            });
    }

    return items;
};

var unload = func(addon) {
    globals.acars.stop();
};

var main = func(addon) {
    globals.acars = ACARS.new();
};
