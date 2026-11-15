use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use App::Dapper::Import;

# The small TOML reader used for Hugo front matter and settings

sub toml { App::Dapper::Import::toml(@_) }

subtest 'strings' => sub {
    is_deeply(toml(q{a = "plain"}), { a => 'plain' }, 'a basic string');
    is_deeply(toml(q{a = "tab\there\nnew \\\\ back \" q"}), { a => qq{tab\there\nnew \\ back " q} }, 'escapes: \t \n \\\\ \"');
    is_deeply(toml(q{a = "x \"y\""}), { a => 'x "y"' }, 'escaped quotes');
    is_deeply(toml(q{a = ""}), { a => '' }, 'empty');
    is_deeply(toml(q{a = 'C:\path\n'}), { a => 'C:\path\n' }, 'a literal string keeps backslashes');
    is_deeply(toml(q{a = ''}), { a => '' }, 'an empty literal');
    is_deeply(toml(q{a = "x # not a comment"}), { a => 'x # not a comment' }, 'a # inside a string');
    is_deeply(toml(q{a = "has #hash" # c}), { a => 'has #hash' }, 'a # inside and a comment after');
    is_deeply(toml(q{a = "x" # comment}), { a => 'x' }, 'a comment after');
    is_deeply(toml(q{a = 'x' # c}), { a => 'x' }, 'a comment after a literal');
    is_deeply(toml(q{a = "x" # it's}), { a => 'x' }, "a comment with an apostrophe after a string");
    is_deeply(toml(q{a = "unterminated}), { a => '"unterminated' }, 'an unterminated string is kept as written');
    is_deeply(toml(q{a = "caf} . "\x{e9}" . q{"}), { a => "caf\x{e9}" }, 'characters outside ASCII');
    is_deeply(toml(q{a = "\u00e9"}), { a => "\x{e9}" }, '\u escape');
    is_deeply(toml(qq{a = """multi\nline"""}), { a => "multi\nline" }, 'a multi-line string');
};

subtest 'numbers, booleans and dates' => sub {
    is_deeply(toml("a = 42"), { a => 42 }, 'an integer');
    is(toml("a = -3.5")->{a}, '-3.5', 'a float, kept as written');
    is(toml("a = 1e3")->{a}, '1e3', 'an exponent');
    is(toml("a = +7")->{a}, '+7', 'a plus sign');
    is(toml("a = 0x1F")->{a}, '0x1F', 'hex is not converted');
    is(toml("a = 1_000")->{a}, '1_000', 'underscores are not removed');
    is_deeply(toml("a = 5 # c"), { a => 5 }, 'a comment after a number');
    is_deeply(toml("a = true\nb = false"), { a => 1, b => 0 }, 'true and false');
    is_deeply(toml("c = True"), { c => 'True' }, 'True is not a boolean');
    is_deeply(toml("a = 2021-06-01T09:00:00Z\nb = 2021-06-01\nc = 09:30:00\nd = 1979-05-27T00:32:00-07:00"),
        { a => '2021-06-01T09:00:00Z', b => '2021-06-01', c => '09:30:00', d => '1979-05-27T00:32:00-07:00' }, 'dates and times as text');
    is_deeply(toml("a = 5 # it's"), { a => 5 }, "a comment with an apostrophe after a number");
};

subtest 'arrays' => sub {
    is_deeply(toml('a = [1, 2, 3]'), { a => [1, 2, 3] }, 'numbers');
    is_deeply(toml(q{e = [1, "two", 'three']}), { e => [1, 'two', 'three'] }, 'mixed');
    is_deeply(toml('a = []'), { a => [] }, 'empty');
    is_deeply(toml('a = [ ]'), { a => [] }, 'empty with a space');
    is_deeply(toml('a = ["x, y", "z]"]'), { a => ['x, y', 'z]'] }, 'commas and brackets inside strings');
    is_deeply(toml(q{a = ["q\"uote", 's']}), { a => ['q"uote', 's'] }, 'escaped quotes inside');
    is_deeply(toml('a = ["a", ]'), { a => ['a'] }, 'a trailing comma');
    is_deeply(toml('a = [true, false, 1.5]'), { a => [1, 0, '1.5'] }, 'booleans and floats');
    is_deeply(toml(qq{a = [\n  "x",\n  "y"\n]\nb = 2}), { a => ['x', 'y'], b => 2 }, 'over several lines');
    is_deeply(toml(qq{categories = [\n  "News",\n]}), { categories => ['News'] }, 'over several lines, trailing comma');
    is_deeply(toml(qq{a = ["x",\n"y"]   # c}), { a => ['x', 'y'] }, 'a comment after the closing line');
    is_deeply(toml(qq{a = ["[",\n"y"]}), { a => ['[', 'y'] }, 'a bracket in a string does not keep it open');
    is_deeply(toml(qq{a = [\n  "x",}), { a => '[ "x",' }, 'never closed: kept as text');
    is_deeply(toml(qq{a = [\n  "x",\n  "y" # c\n]}), { a => ['x', 'y'] }, 'a comment inside');
    is_deeply(toml('a = [[1, 2], [3]]'), { a => [[1, 2], [3]] }, 'nested arrays');
};

subtest 'keys and tables' => sub {
    is_deeply(toml(qq{"my key" = 1\n'lit key' = 2\nbare-key_1 = 3}), { 'my key' => 1, 'lit key' => 2, 'bare-key_1' => 3 }, 'quoted and bare keys');
    is_deeply(toml("x = 1\nx = 2"), { x => 2 }, 'the last of a repeated key wins');
    is_deeply(toml("  indented = 1  "), { indented => 1 }, 'spaces around');
    is_deeply(toml("k=v"), { k => 'v' }, 'no spaces around =, a bare value');
    is_deeply(toml("noequals\n= nokey\nk = 1"), { k => 1 }, 'lines that are not key = value are skipped');
    is_deeply(toml("# only a comment\n\n   \n"), {}, 'nothing but comments and blank lines');
    is_deeply(toml(''), {}, 'empty');
    is_deeply(toml("x = 1\r\ny = 2\r\n"), { x => 1, y => 2 }, 'Windows line endings');
    is_deeply(toml("k = { inline = 1 }"), { k => '{ inline = 1 }' }, 'an inline table is kept as text');

    is_deeply(toml(qq{[params]\nmood = "happy"\n[params.deep]\nx = 1\n[other]\ny = 2}),
        { params => { mood => 'happy', deep => { x => 1 } }, other => { y => 2 } }, 'tables and dotted tables');
    is_deeply(toml("[a.b.c]\nd = 1"), { a => { b => { c => { d => 1 } } } }, 'three deep');
    is_deeply(toml("[ params ]\ny = 2"), { params => { y => 2 } }, 'spaces inside the brackets');
    is_deeply(toml("top = 1\n[t]\nin = 2"), { top => 1, t => { in => 2 } }, 'keys before the first table are at the top');
    is_deeply(toml(qq{[x.y]\nz = "deep"\n[x]\nw = 1}), { x => { y => { z => 'deep' }, w => 1 } }, 'a table added to after its child');
    is_deeply(toml(qq{["quoted.key"]\nx = 1}), { quoted => { key => { x => 1 } } }, 'a quoted table name is still split on dots');
    is_deeply(toml(qq{[[menu.main]]\nname = "Home"\n[[menu.main]]\nname = "About"}), { menu => { main => { name => 'About' } } },
        'an array of tables is read as one table (the last wins)');
    is_deeply(toml("x = 1\n[params] # c\ny = 2"), { x => 1, params => { y => 2 } }, 'a comment after a table name');
    is_deeply(toml("a.b = 4"), { a => { b => 4 } }, 'a dotted key');
};

subtest 'a whole front matter' => sub {
    is_deeply(toml(<<'TOML'), {
title = "TOML post"
date = 2021-06-01T09:00:00Z
draft = false
weight = 10
tags = ["a", "b"]
categories = [
  "News",
  "Perl",
]
aliases = ["/old/toml/"]
description = 'It''s'
[params]
  mood = "happy"
  [params.author]
    name = "Me"
TOML
        title => 'TOML post', date => '2021-06-01T09:00:00Z', draft => 0, weight => 10, tags => ['a', 'b'],
        categories => ['News', 'Perl'], aliases => ['/old/toml/'], description => q{'It''s'},
        params => { mood => 'happy', author => { name => 'Me' } },
    }, 'everything together');
};

done_testing();
