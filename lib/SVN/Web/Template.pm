package SVN::Web::Template;

sub template {
    return { header => "<html><!-- css, etc here -->\n",
	     footer => "Powered by SVN::Web</html>",
	   };
}

1;
