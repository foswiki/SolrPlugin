/*
 * Copyright (c) 2013-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
jQuery(function($) {
  $(".solrSearchHits .foswikiProfileInfo:nth-child(3n+1)").livequery(function() {
    $(this).addClass("first");
  });
});
