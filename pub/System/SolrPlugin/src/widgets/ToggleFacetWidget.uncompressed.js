/*
 * Copyright (c) 2013-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function ($) {

  AjaxSolr.ToggleFacetWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    options: {
      templateName: '#solrToggleFacetTemplate',
      value: null,
      inverseValue: null,
      inverse: false,
      exclude: false,
      checked: undefined,
    },
    checkbox: null,

    afterRequest: function () {
      var self = this;

      if (self.isSelected(self.options.value)) {
        if (self.options.inverse || self._isExclude) {
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

    _updateValues: function(isChecked) {
        var self = this;

        self._isExclude = false;

        if (isChecked) {
          if (self.options.inverse) {
            self.remove(self.options.value);
            if (self.options.exclude) {
              self._isExclude = true;
              self.add(self.options.value, true);
            }
            if (self.options.inverseValue) {
              self.add(self.options.inverseValue);
            }
          } else {
            if (self.options.inverseValue) {
              self.remove(self.options.inverseValue);
            }
            if (self.options.exclude) {
              self.remove(self.options.value, true);
            }
            self.add(self.options.value);
          }
        } else {
          if (self.options.inverse) {
            self.add(self.options.value);
            if (self.options.exclude) {
              self.remove(self.options.value, true);
            }
            if (self.options.inverseValue) {
              self.remove(self.options.inverseValue);
            }
          } else {
            if (self.options.inverseValue) {
              self.add(self.options.inverseValue);
            }
            if (self.options.exclude) {
              self._isExclude = true;
              self.add(self.options.value, true);
            }
            self.remove(self.options.value);
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
        self.$target.find("input[type='checkbox']").on("change", function() {
          self._updateValues($(this).is(":checked"));
          self.doRequest(0);
        });

      if (typeof(self.options.checked) !== 'undefined') {
        self._updateValues(self.options.checked);
      }
    }

  });

  AjaxSolr.Helpers.build("ToggleFacetWidget");


})(jQuery);


