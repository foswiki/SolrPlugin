/*
 * Copyright (c) 2013-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.SpellcheckWidget = AjaxSolr.AbstractSpellcheckWidget.extend({
    defaults: {
      "spellcheck": true,
      "spellcheck.count": 3,
      "spellcheck.collate": true,
      "spellcheck.onlyMorePopular": false,
      "spellcheck.maxCollations": 3,
      "spellcheck.maxCollationTries": 10,
      //"spellcheck.extendedResults": true,
      "templateName": "#solrSpellCorrectionTemplate"
    },
    options: {},
    $target: null,
    template: null,

    beforeRequest: function() {
      var self = this;

      self._super();

      self.$target.empty();
    },

    handleSuggestions: function() {
      var self = this;
      
      self.$target.html(self.template.render({
        suggestions: self.suggestions
      }));

      //console.log("suggestions=",self.suggestions);

      self.$target.find("a").click(function() {
        self.manager.store.addByValue("q", $(this).text());
        self.manager.doRequest(0);
        return false;
      });
    },

    init: function() {
      var self = this;

      self.$target = $(self.target);
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());
      self.template = $.templates(self.options.templateName);

      for (var name in self.options) {
        if (name.match(/^spellcheck/)) {
          self.manager.store.addByValue(name, self.options[name]);
        }
      }
    }
  });

  AjaxSolr.Helpers.build("SpellcheckWidget");

})(jQuery);


