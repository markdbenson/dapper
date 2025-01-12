package App::Dapper::Init;

=head1 NAME

App::Dapper::Init - Default project files to use when a "dapper init" command is used.

=head1 DESCRIPTION

When using the dapper tool to initialize an empty directory with a new site, the files
that are written to disk are contained in this file. For instance, the YAML project
file, a layout template, and a starter post.

=cut

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.8.0;
use strict;
use warnings FATAL => 'all';

use App::Dapper::Utils;

my $source_index_name = "index.md";
my $source_index_content = <<'SOURCE_INDEX_CONTENT';
---
layout: index
title: Welcome
---

Hello world.

SOURCE_INDEX_CONTENT

my $templates_index_name = "index.html";
my $templates_index_content = <<'TEMPLATES_INDEX_CONTENT';
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
  <title>[% page.title %]</title>
  <meta http-equiv="content-type" content="text/html; charset=UTF-8">
</head>

<body>

[% page.content %]

</body>
</html>

TEMPLATES_INDEX_CONTENT

my $proj_file_template_content = <<'PROJ_FILE_TEMPLATE';
# Dapper configuration file
---
name : My Site

PROJ_FILE_TEMPLATE

=head2 init

Initialize a Dapper project. This method creates a config file, source and template directories.
After calling this method, the project may be built.

=cut

sub init {
    my ($source, $output, $layout, $config) = @_;

    App::Dapper::Utils::create_file($config, $proj_file_template_content);

    App::Dapper::Utils::create_dir($source);
    App::Dapper::Utils::create_file("$source/$source_index_name", $source_index_content);

    App::Dapper::Utils::create_dir($layout);
    App::Dapper::Utils::create_file("$layout/$templates_index_name", $templates_index_content);
}

1;
