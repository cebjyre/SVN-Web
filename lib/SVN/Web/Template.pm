package SVN::Web::Template;

sub template {
    return { header => q|<html><!-- css, etc here -->
<div id="navpath">
[% url = [script,repos,''] %]
[% url = url.join('/') %]
[% urlpath = ['',''] %]
<a href="[% url %]">[[% repos %]]</a>
[% FOREACH p = navpaths %]
  [% CALL urlpath.splice(-1, 0, p) %]
  [% IF loop.count == loop.size %]
    [% IF p %]
/ [% p %]
    [% END %]
  [% ELSE %]
/  <a href="[% url %][% action %][% urlpath.join('/') %]">[% p %]</a>
  [% END %]
[% END %]
</div>
|,
	     footer => '<div align="right"><em>Powered by SVN::Web</em></div>
</html>
',
	   };
}

1;
