#!/usr/bin/python
import sys, json, yaml

try:
    if sys.argv[1] == "-":
            y=yaml.load(sys.stdin.read())
    else:
        with open(sys.argv[1]) as i:
            y=yaml.load(i.read())
except:
    print "Usage: \n\t%s [file.yml|-] {key} [key} ...\n"
    print "Dumps yaml content as beuatified json\n"
    print "if argv[1] is -, reads yaml from stdin\n"
    print "if optional key is given, key is extracted and printed to stdout\n"
else:
    i=2
    while len(sys.argv) > i:
        y=y.get(sys.argv[i])
        i += 1
    if isinstance(y,(str,unicode)) is False and isinstance(y,(list,dict)) is True:
        print json.dumps(y,indent=2)
    else:
        print y

