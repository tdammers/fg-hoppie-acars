var ACARS = {
    new: func () {
        return {
            parents: [ACARS],
            downlinkNode: props.globals.getNode('/hoppie/downlink', 1),
            uplinkNode: props.globals.getNode('/hoppie/uplink', 1),
            formattedLogNode: props.globals.getNode('/hoppie/formatted-log', 1),
            urlTemplate: nil,
            pollTimer: nil,
            autostartListener: nil,
        };
    },

    start: func () {
        me.recalcUrlTemplate();
        if (me.pollTimer == nil) {
            me.pollTimer = maketimer(1, me, me.poll);
            me.pollTimer.simulatedTime = 1;
            me.pollTimer.singleShot = 0;
        }
        if (!me.pollTimer.isRunning) {
            me.pollTimer.start();
        }
        setprop('/hoppie/status-text', 'running');
    },

    stop: func () {
        if (me.pollTimer != nil) {
            me.pollTimer.stop();
        }
        setprop('/hoppie/status-text', 'stopped');
    },

    enableAutostart: func () {
        if (me.autostartListener == nil) {
            var self = me;
            me.autostartListener = setlistener('/sim/swift/serverRunning', func (node) {
                if (node.getBoolValue()) {
                    self.start();
                }
                else {
                    self.stop();
                }
            });
        }
    },

    disableAutostart: func () {
        if (me.autostartListener != nil) {
            removelistener(me.autostartListener);
            me.autostartListener = nil;
        }
        me.stop();
    },

    recalcUrlTemplate: func () {
        var template =
                getprop('/sim/hoppie/url') or
                    'http://www.hoppie.nl/acars/system/connect.html?logon={logon}&from={from}&to={to}&type={type}&packet={packet}';
        var compiled = string.compileTemplate(template);
        if (compiled != nil) {
            me.urlTemplate = compiled;
        }
        else {
            debug.warn("Invalid URL template, ACARS will not work");
            me.urlTemplate = nil;
        }
    },

    clearMessages: func() {
        me.formattedLogNode.setValue('');
    },

    getCurrentTimestamp: func () {
        var utcNode = props.globals.getNode('/sim/time/utc');
        return sprintf('%04u%02u%02uT%02u%02u%02u',
            utcNode.getValue('year'),
            utcNode.getValue('month'),
            utcNode.getValue('day'),
            utcNode.getValue('hour'),
            utcNode.getValue('minute'),
            utcNode.getValue('second'));
    },

    # Low-level ACARS send function
    send: func (to='', type='telex', packet='', done=nil, failed=nil) {
        if (typeof(me.urlTemplate) != 'func') {
            debug.warn("Invalid URL template, can't send ACARS message");
            return;
        }
        var from = getprop('/sim/multiplay/callsign');
        var params = {
                'logon': urlencode(getprop('/sim/hoppie/token')),
                'from': urlencode(from),
                'to': urlencode(to),
                'type': urlencode(type),
                'packet': urlencode(packet),
            };
        var url = me.urlTemplate(params);

        var msgNode = nil;
        if (type != 'poll') {
            msgNode = me.downlinkNode;
            msgNode.setValue('from', from);
            msgNode.setValue('to', to);
            msgNode.setValue('type', type);
            msgNode.setValue('packet', packet);
            var timestamp = me.getCurrentTimestamp();
            msgNode.setValue('timestamp', timestamp);
            me.appendLog(sprintf(">>>> %s %s %s\n%s\n", substr(timestamp, 9, 4), to, type, packet));
            msgNode.setValue('status', 'sending');
        }
        http.load(url)
            .done(func(r) {
                if (msgNode != nil) {
                    msgNode.setValue('status', 'sent');
                }
                if (typeof(done) == 'func') {
                    call(done, [r.response]);
                }
            })
            .fail(func {
                if (msgNode != nil) {
                    msgNode.setValue('status', 'error');
                }
                if (typeof(failed) == 'func') {
                    call(failed, [r.response]);
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
        var timestamp = me.getCurrentTimestamp();
        msgNode.setValue('type', type);
        msgNode.setValue('from', from);
        msgNode.setValue('to', to);
        msgNode.setValue('packet', packet);
        msgNode.setValue('timestamp', timestamp);
        msgNode.setValue('status', 'new');
        me.appendLog(sprintf("<<<< %s %s %s\n%s\n", substr(timestamp, 9, 4), from, type, packet));
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
            # consume leading '{'
            if (left(str, 1) != '{') {
                debug.dump('PARSER ERROR 1: ' ~ str);
                return items;
            }
            str = substr(str, 1);

            # skip whitespace
            while (left(str, 1) == ' ') str = substr(str, 1);

            # from
            i = find(' ', str);
            if (i < 0) {
                debug.dump('PARSER ERROR 2: ' ~ str);
                return items;
            }
            var from = left(str, i);
            str = substr(str, i + 1);

            # skip whitespace
            while (left(str, 1) == ' ') str = substr(str, 1);

            # type
            i = find(' ', str);
            if (i < 0) {
                debug.dump('PARSER ERROR 3: ' ~ str);
                return items;
            }
            var type = left(str, i);
            str = substr(str, i + 1);

            # skip whitespace
            while (left(str, 1) == ' ') str = substr(str, 1);

            # packet
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

var findMenuNode = func (create=0) {
    var equipmentMenuNode = props.globals.getNode('/sim/menubar/default/menu[5]');
    foreach (var item; equipmentMenuNode.getChildren('item')) {
        if (item.getValue('name') == 'acars-hoppie') {
            return item;
        }
    }
    if (create) {
        return equipmentMenuNode.addChild('item');
    }
    else {
        return nil;
    }
};

var unload = func(addon) {
    globals.hoppieAcars.stop();
    var myMenuNode = findMenuNode();
    if (myMenuNode != nil) {
        myMenuNode.remove();
        fgcommand('reinit', {'subsystem': 'gui'});
    }
};

var main = func(addon) {
    globals.hoppieAcars = ACARS.new();
    if (getprop('/sim/hoppie/autostart')) {
        globals.hoppieAcars.enableAutostart();
    }
    var myMenuNode = findMenuNode(1);
    myMenuNode.setValues({
        enabled: 'true',
        name: 'acars-hoppie',
        label: 'ACARS (Hoppie)',
        binding: {
            'command': 'dialog-show',
            'dialog-name': 'addon-hoppie-dialog',
        },
    });
    fgcommand('reinit', {'subsystem': 'gui'});
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
