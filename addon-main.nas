var ACARS = {
    new: func () {
        return {
            parents: [ACARS],
            downlinkNode: props.globals.getNode('/acars/downlink', 1),
            uplinkNode: props.globals.getNode('/acars/uplink', 1),
            formattedLogNode: props.globals.getNode('/acars/formatted-log', 1),
            pollTimer: nil,
        };
    },

    start: func () {
        if (me.pollTimer == nil) {
            me.pollTimer = maketimer(1, me, me.poll);
            me.pollTimer.simulatedTime = 1;
            me.pollTimer.singleShot = 0;
        }
        if (!me.pollTimer.isRunning) {
            me.pollTimer.start();
        }
        setprop('/acars/status-text', 'running');
    },

    stop: func () {
        if (me.pollTimer != nil) {
            me.pollTimer.stop();
        }
        setprop('/acars/status-text', 'stopped');
    },

    clearMessages: func() {
        me.formattedLogNode.setValue('');
    },

    # Low-level ACARS send function
    send: func (to='', type='telex', packet='', done=nil) {
        var logon = getprop('/sim/hoppie/token');
        var from = getprop('/sim/multiplay/callsign');
        var url = 'http://www.hoppie.nl/acars/system/connect.html?' ~
                  'logon=' ~ urlencode(logon) ~
                  '&from=' ~ urlencode(from) ~ 
                  '&to=' ~ urlencode(to) ~
                  '&type=' ~ urlencode(type) ~
                  '&packet=' ~ urlencode(packet);
        var msgNode = nil;
        if (type != 'poll') {
            msgNode = me.downlinkNode;
            msgNode.setValue('from', from);
            msgNode.setValue('to', to);
            msgNode.setValue('type', type);
            msgNode.setValue('packet', packet);
            me.appendLog(sprintf(">>>> %s %s\n%s\n", to, type, packet));
            msgNode.setValue('status', 'sending');
        }
        http.load(url)
            .done(func(r) {
                if (msgNode != nil) {
                    msgNode.setValue('status', 'sent');
                }
                if (typeof(done) == 'func') {
                    done(r.response);
                }
            })
            .fail(func {
                if (msgNode != nil) {
                    msgNode.setValue('status', 'error');
                }
            });
    },

    poll: func () {
        me.send('ZZZZ', 'poll', '', func(rp) {
            var items = me.parsePollResponse(rp);
            foreach (var item; items) {
                me.processResponse(item);
            }
        });
    },

    processResponse: func(item) {
        me.uplink(item.type, item.from, item.packet);
    },

    uplink: func(type, from, packet) {
        var to = getprop('/sim/multiplay/callsign');
        var msgNode = me.uplinkNode;
        msgNode.setValue('type', type);
        msgNode.setValue('from', from);
        msgNode.setValue('to', to);
        msgNode.setValue('packet', packet);
        msgNode.setValue('status', 'new');
        me.appendLog(sprintf("<<<< %s %s\n%s\n", from, type, packet));
    },

    appendLog: func(text) {
        var formattedNode = me.formattedLogNode;
        formattedNode.setValue(formattedNode.getValue() ~ text);
    },

    parsePollResponse: func (str) {
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
    },
};

var unload = func(addon) {
    globals.acars.stop();
};

var main = func(addon) {
    globals.acars = ACARS.new();
};

var urlencode = func(str) {
    var out = '';
    var c = '';
    var n = 0;
    for (var i = 0; i < size(str); i += 1) {
        n = str[i];
        if (string.isalnum(n)) {
            out = out ~ chr(n);
        }
        elsif (n == 32) {
            out = out ~ '+';
        }
        else {
            out = out ~ sprintf('%%%02x', n);
        }
    }
    return out;
};
