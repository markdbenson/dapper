package Text::Dapper::Init;

use 5.006;
use strict;
use warnings FATAL => 'all';

use Text::Dapper::Utils;

my $source_dir_name = "_source";
my $templates_dir_name = "_layout";

my $source_index_name = "$source_dir_name/index.md";
my $source_index_content = <<'SOURCE_INDEX_CONTENT';
---
layout: index
title: Hello World
---

Hello world.
SOURCE_INDEX_CONTENT

my $templates_index_name = "$templates_dir_name/index.html";
my $templates_index_content = <<'TEMPLATES_INDEX_CONTENT';
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
  <title>{{ page.title }}</title>
  <meta http-equiv="content-type" content="text/html; charset=iso-8859-1">
</head>

<body>

{{ page.content }}

</body>
</html>

TEMPLATES_INDEX_CONTENT

my $proj_file_template_name = "_config.yml";
my $proj_file_template_content = <<'PROJ_FILE_TEMPLATE';
---
name : My Site
source : _source/
output : _output/
layout : _layout/
ignore :
    - "^\."
    - "^_"
    - "^dapper$"

PROJ_FILE_TEMPLATE

sub init {
    Text::Dapper::Utils::create_file($proj_file_template_name, $proj_file_template_content);

    Text::Dapper::Utils::create_dir($source_dir_name);
    Text::Dapper::Utils::create_file($source_index_name, $source_index_content);

    Text::Dapper::Utils::create_dir($templates_dir_name);
    Text::Dapper::Utils::create_file($templates_index_name, $templates_index_content);
}

1;
