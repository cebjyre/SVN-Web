package SVN::Web::Template;

sub template {
    return { header => q|<html><!-- css, etc here -->
[% UNLESS nonav %]
<div id="navpath">
<a href="[% script %]">Repository list</a><br />
  [% url = [script,repos,''] %]
  [% url = url.join('/') %]
  [% urlpath = ['',''] %]
<a href="[% url %]">[[% repos %]]</a>
  [% FOREACH p = navpaths %]
    [% CALL urlpath.splice(-1, 0, p) %]
    [% IF loop.count == loop.size %]
      [% IF p %]
/   [% p %]
      [% END %]
    [% ELSE %]
/    <a href="[% url %][% action %][% urlpath.join('/') %]">[% p %]</a>
    [% END %]
  [% END %]
</div>
[% END %]
|,
	     footer => '<div align="right"><em>[%|l%]Powered by SVN::Web[%END%]</em></div>
</html>
',
	   };
}

1;
