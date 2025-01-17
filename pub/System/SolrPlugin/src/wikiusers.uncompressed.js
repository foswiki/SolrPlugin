/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
jQuery(function($) {
  $(".solrSearchHits .foswikiProfileInfo:nth-child(3n+1)").livequery(function() {
    $(this).addClass("first");
  });
});
