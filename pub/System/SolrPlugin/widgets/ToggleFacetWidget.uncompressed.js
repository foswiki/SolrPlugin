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

  AjaxSolr.ToggleFacetWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    options: {
      templateName: '#solrToggleFacetTemplate',
      value: null,
      inverseValue: null,
      inverse: false
    },
    checkbox: null,

    afterRequest: function () {
      var self = this;

      if (self.isSelected(self.options.value)) {
        if (self.options.inverse) {
          self.checkbox.prop("checked", false);
        } else {
          self.checkbox.prop("checked", true);
        }
      } else {
        if (self.options.inverse) {
          self.checkbox.prop("checked", true);
        } else {
          self.checkbox.prop("checked", false);
        }
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.$target.append($(self.options.templateName).render({
        id: AjaxSolr.Helpers.getUniqueID(),
        title: self.options.title
      }));

      self.checkbox = 
        self.$target.find("input[type='checkbox']").change(function() {
          if ($(this).is(":checked")) {
            if (self.options.inverse) {
              self.unclickHandler(self.options.value).call(self);
              if (self.options.inverseValue) {
                self.clickHandler(self.options.inverseValue).call(self);
              }
            } else {
              self.clickHandler(self.options.value).call(self);
              if (self.options.inverseValue) {
                self.unclickHandler(self.options.inverseValue).call(self);
              }
            }
          } else {
            if (self.options.inverse) {
              self.clickHandler(self.options.value).call(self);
              if (self.options.inverseValue) {
                self.unclickHandler(self.options.inverseValue).call(self);
              }
            } else {
              self.unclickHandler(self.options.value).call(self);
              if (self.options.inverseValue) {
                self.clickHandler(self.options.inverseValue).call(self);
              }
            }
          }
        });

      if (self.options.inverse) {
        self.add(self.options.value);
        if (self.options.inverseValue) {
          self.remove(self.options.inverseValue);
        }
      } else {
        if (self.options.inverseValue) {
          self.add(self.options.inverseValue);
        }
        self.remove(self.options.value);
      }
    }

  });

  AjaxSolr.Helpers.build("ToggleFacetWidget");


})(jQuery);


