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
        print("ACARS start");
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
        print("ACARS stop");
        if (me.pollTimer != nil) {
            me.pollTimer.stop();
        }
        setprop('/acars/status-text', 'stopped');
    },

    clearMessages: func() {
        me.downlinkNode.removeAllChildren();
        me.uplinkNode.removeAllChildren();
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
        print("Request: " ~ url);
        if (type != 'poll') {
            msgNode = me.uplinkNode.addChild('message');
            msgNode.setValue('type', type);
            msgNode.setValue('from', from);
            msgNode.setValue('packet', packet);
            msgNode.setValue('status', 'pending');
            if (type == 'cpdlc') {
                var cpdlc = me.parseCPDLC(packet);
                msgNode.setValues(cpdlc);
                me.appendLog(
                    sprintf(">>>> %s %s %s/%s %s\n%s\n",
                        to, type,
                        cpdlc.min, cpdlc.mrn, cpdlc.ra,
                        string.join("\n", cpdlc.message)));
            }
            else {
                me.appendLog(sprintf(">>>> %s %s\n%s\n", to, type, packet));
            }
            msgNode.setValue('status', 'sending');
        }
        http.load(url).done(func(r) {
            print("Response: " ~ r.response);
            if (msgNode != nil) {
                msgNode.setValue('status', 'sent');
            }
            if (typeof(done) == 'func') {
                done(r.response);
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
        me.downlink(item.type, item.from, item.packet);
    },

    downlink: func(type, from, packet) {
        var msgNode = me.downlinkNode.addChild('message');
        msgNode.setValue('type', type);
        msgNode.setValue('from', from);
        msgNode.setValue('packet', packet);
        msgNode.setValue('status', 'new');
        if (type == 'cpdlc') {
            var cpdlc = me.parseCPDLC(packet);
            msgNode.setValues(cpdlc);
            me.appendLog(
                sprintf("<<<< %s %s %s/%s %s\n%s\n",
                    from, type,
                    cpdlc.min, cpdlc.mrn, cpdlc.ra,
                    string.join("\n", cpdlc.message)));
        }
        else {
            me.appendLog(sprintf("<<<< %s %s\n%s\n", from, type, packet));
        }
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

    parseCPDLC: func (str) {
        # /data2/654/3/NE/LOGON ACCEPTED
        var result = split('/', string.uc(str));
        if (result[0] != '') {
            debug.dump('PARSER ERROR 10: expected leading slash in ' ~ str);
            return nil;
        }
        if (result[1] != 'DATA2') {
            debug.dump('PARSER ERROR 11: expected `data2` in ' ~ str);
            return nil;
        }
        var min = result[2];
        var mrn = result[3];
        var ra = result[4];
        var message = subvec(result, 5);
        return {
            min: min,
            mrn: mrn,
            ra: ra,
            message: message,
        }
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
