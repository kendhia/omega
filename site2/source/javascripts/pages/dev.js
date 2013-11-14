/* Omega Dev Page JS
 *
 * Copyright (C) 2013 Mohammed Morsi <mo@morsi.org>
 *  Licensed under the AGPLv3+ http://www.gnu.org/licenses/agpl.txt
 */

//= require "ui/canvas"

Omega.Pages.Dev = function(){
  this.config  = Omega.Config;
  this.node    = new Omega.Node(this.config);
  this.canvas  = new Omega.UI.Canvas({page: this});
};

Omega.Pages.Dev.prototype = {
  wire_up : function(){
    this.canvas.wire_up();
  },

  custom_operations : function(){
    var star_loc = new Omega.Location({x:0,y:0,z:0});
    var star   = new Omega.Star({location: star_loc});
    var children = [star];
    var system = new Omega.SolarSystem({children: children});

    this.canvas.setup();
    this.canvas.set_scene_root(system);
this.canvas.add(this.canvas.axis);
this.canvas.add(this.canvas.skybox);
    this.canvas.animate();
  }
};

$(document).ready(function(){
  var dev = new Omega.Pages.Dev();
  dev.wire_up();
  dev.custom_operations();
});