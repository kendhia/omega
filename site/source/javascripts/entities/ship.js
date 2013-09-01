/* Omega Javascript Ship
 *
 * Copyright (C) 2013 Mohammed Morsi <mo@morsi.org>
 *  Licensed under the AGPLv3+ http://www.gnu.org/licenses/agpl.txt
 */

/* Omega Ship
 */
function Ship(args){
  $.extend(this, new Entity(args));
  $.extend(this, new CanvasComponent(args));

  var ship = this;
  this.json_class = 'Manufactured::Ship';
  this.ignore_properties.push('trails');

  this.location = new Location(this.location);

  /* helper to lookup mining target in local registry
   *
   * (needs to be defined before update is called)
   */
  this.resolve_mining_target = function(mining_target){
    var sys  = Entities().get(this.system_id);
    var asts = sys ? sys.asteroids : [];
    for(var a in asts){
      if(asts[a].id == mining_target.entity_id){
        this.mining = mining_target;
        this.mining.entity = asts[a];
        break;
      }
    }
  }

  /* override update
   */
  this.old_update = this.update;
  this.update = function(oargs){
    var args = $.extend({}, oargs); // copy args

    var to_remove = [];

    if(args.location && this.location){
      this.location.update(args.location);

      // XXX since Location ignore movement strategy need
      // to manually update it here
      if(args.location.movement_strategy)
        this.location.movement_strategy = args.location.movement_strategy;

      if(this.mesh){
        this.mesh.position.x = this.location.x;
        this.mesh.position.y = this.location.y;
        this.mesh.position.z = this.location.z;
        this.set_orientation(this.mesh, true)
      }

      if(this.trails){
        for(var t in this.trails){
          var trail = this.trails[t];
          var conf_trail = $omega_config.resources[ship.type].trails[t];
          trail.position.x = this.location.x + conf_trail[0];
          trail.position.y = this.location.y + conf_trail[1];
          trail.position.z = this.location.z + conf_trail[2];
          this.set_orientation(trail, false);

          if(!this.location.movement_strategy ||
             this.location.movement_strategy.json_class ==
             'Motel::MovementStrategies::Stopped'){
             if(this.components.indexOf(trail) != -1)
               to_remove.push(trail);

          }else if(this.components.indexOf(trail) == -1){
            this.components.push(trail);
          }
        }
      }

      if(this.attack_particles){
        this.attack_particles.position.x = this.location.x;
        this.attack_particles.position.y = this.location.y;
        this.attack_particles.position.z = this.location.z;
      }

      if(this.mining_line){
        this.mining_line_geo.vertices[0].x = this.location.x;
        this.mining_line_geo.vertices[0].y = this.location.y;
        this.mining_line_geo.vertices[0].z = this.location.z;
      }

      delete args.location;

    }

    // handle attack state changes
    if(args.attacking){
      if(this.attack_particles){
        if(this.components.indexOf(this.attack_particles) == -1)
          this.components.push(this.attack_particles);

        this.refresh_attack_particles(this.attack_particles.geometry,
                                      args.attacking.location)
      }

    }else if(this.attacking){
      if(this.attack_particles)
        to_remove.push(this.attack_particles)
    }

    // handle mining state changes
    if(args.mining){
      this.resolve_mining_target(args.mining);

      if(this.mining_line){
        if(this.components.indexOf(this.mining_line) == -1)
          this.components.push(this.mining_line);

        this.mining_line_geo.vertices[1].x = this.mining.entity.location.x;
        this.mining_line_geo.vertices[1].y = this.mining.entity.location.y;
        this.mining_line_geo.vertices[1].z = this.mining.entity.location.z;
      }

    }else if(this.mining && this.mining_line){
      to_remove.push(this.mining_line);
    }

    if(this.current_scene) this.current_scene.reload_entity(this, function(s, e){
      for(var r in to_remove)
        e.components.splice(e.components.indexOf(to_remove[r]), 1);
    });

    // update visual attributes depending on if ship is selected
    if(this.mesh){
      if(this.selected){
        if(typeof this.origEmissive === "undefined" ||
                  this.origEmissive == null)
          this.origEmissive = this.mesh.material.emissive.getHex();
        this.mesh.material.emissive.setHex(0xff0000);
      }else{
        if(typeof this.origEmissive !== "undefined" &&
                  this.origEmissive != null){
          this.mesh.material.emissive.setHex(this.origEmissive);
          this.origEmissive = null;
        }
      }
    }

    // do not update components from args
    if(args.components) delete args.components;

    this.old_update(args);
  }

  this.refresh = function(){
    // trigger a blank update to refresh components from current state
    this.update(this);
  }

  // XXX run new update method
  // (a bit redunant w/ update invoked in Entity constructor)
  this.update(args);

  this.belongs_to_user = function(user){
    return this.user_id == user;
  }
  this.belongs_to_current_user = function(){
    return Session.current_session != null &&
           this.belongs_to_user(Session.current_session.user_id);
  }

  /* helper to set orientation
   */
  this.set_orientation = function(component, is_mesh){
    // apply base mesh rotation
    var rotation = $omega_config.resources[this.type].rotation
    component.rotation.x = component.rotation.y = component.rotation.z = 0;
    if(rotation){
      component.rotation.x = rotation[0];
      component.rotation.y = rotation[1];
      component.rotation.z = rotation[2];
    }
    component.matrix.setRotationFromEuler(component.rotation);

    // set location orientation
    var oax = cp(0, 0, 1, this.location.orientation_x,
                          this.location.orientation_y,
                          this.location.orientation_z);
    var oab = abwn(0, 0, 1, this.location.orientation_x,
                            this.location.orientation_y,
                            this.location.orientation_z);

    // XXX edge case if facing straight back to preserve 'top'
    // TODO expand this to cover all cases where oab > 1.57 or < -1.57
    if(Math.abs(oab - Math.PI) < 0.0001) oax = [0,1,0];
    var orm = new THREE.Matrix4().makeRotationAxis({x:oax[0], y:oax[1], z:oax[2]}, oab);
    orm.multiplySelf(component.matrix);
    component.rotation.setEulerFromRotationMatrix(orm);

    // rotate everything other than mesh around mesh itself
    if(!is_mesh && Math.abs(oab) > 0.0001){
      // component position is relative to world, need to translate 
      // it to being relative to mesh before rotating (and after again)
      var pos = rot(component.position.x - this.location.x,
                    component.position.y - this.location.y,
                    component.position.z - this.location.z,
                    oab, oax[0], oax[1], oax[2])
      component.position.x = pos[0] + this.location.x;
      component.position.y = pos[1] + this.location.y;
      component.position.z = pos[2] + this.location.z;
    }
  }

  // instantiate mesh to draw ship on canvas
  this.create_mesh = function(){
    if(this.mesh_geometry == null) return;
    this.mesh =
      UIResources().cached("ship_" + this.id + "_mesh",
        function(i) {
          var mesh = new THREE.Mesh(ship.mesh_geometry, ship.mesh_material);
          mesh.position.x = ship.location.x;
          mesh.position.y = ship.location.y;
          mesh.position.z = ship.location.z;

          var scale = $omega_config.resources[ship.type].scale;
          if(scale){
            mesh.scale.x = scale[0];
            mesh.scale.y = scale[1];
            mesh.scale.z = scale[2];
          }

          ship.set_orientation(mesh, true);
          return mesh;
        });

    if(this.hp > 0){
      this.clickable_obj = this.mesh;
      this.components.push(this.mesh);
    }

    // reload entity if already in scene
    if(this.current_scene) this.current_scene.reload_entity(this);
  }

  this.mesh_material =
    UIResources().cached("ship_"+this.type+"_mesh_material",
      function(i) {
        var path = UIResources().images_path + $omega_config.resources[ship.type]['material'];
        var t = UIResources().load_texture(path);
        // lambert material is more resource intensive than basic and
        // requires a light source but is needed to modify emissive
        // properties for selection indication in update above
        return new THREE.MeshLambertMaterial({map: t, overdraw: true});
      });

  this.mesh_geometry =
    UIResources().cached('ship_'+this.type+'_mesh_geometry',
      function(i) {
        var path = UIResources().images_path + $omega_config.resources[ship.type]['geometry'];
        UIResources().load_geometry(path, function(geo){
          ship.mesh_geometry = geo;
          UIResources().set('ship_'+this.type+'_mesh_geometry', ship.mesh_geometry)
          ship.create_mesh();
        })
        return null;
      });

  this.create_mesh();

  // create trail at the specified coordinate relative to ship
  this.create_trail = function(x,y,z){
    //// create a particle system for ship trail
    var plane = 5, lifespan = 20;
    var pMaterial =
      UIResources().cached('ship_tail_material',
        function(i) {
          return new THREE.ParticleBasicMaterial({
                       color: 0xFFFFFF, size: 20,
                       map: UIResources().load_texture("images/particle.png"),
                       blending: THREE.AdditiveBlending, transparent: true });
        });

    // FIXME cache this & particle system (requires a cached instance
    // for each ship tail created)
    var particles = new THREE.Geometry();
    for(var i = 0; i < plane; ++i){
      for(var j = 0; j < plane; ++j){
        var pv = new THREE.Vector3(i, j, 0);
        pv.velocity = Math.random();
        pv.lifespan = Math.random() * lifespan;
        if(i >= plane / 4 && i <= 3 * plane / 4 &&
           j >= plane / 4 && j <= 3 * plane / 4 ){
             pv.lifespan *= 2;
             pv.velocity *= 2;
        }
        pv.olifespan = pv.lifespan;
        particles.vertices.push(pv)
      }
    }

    var particleSystem = new THREE.ParticleSystem(particles, pMaterial);
    particleSystem.position.x = x;
    particleSystem.position.y = y;
    particleSystem.position.z = z;
    particleSystem.sortParticles = true;

    particleSystem.update_particles = function(){
      var p = plane*plane;
      while(p--){
        var pv = this.geometry.vertices[p]
        pv.z -= pv.velocity;
        pv.lifespan -= 1;
        if(pv.lifespan < 0){
          pv.z = 0;
          pv.lifespan = pv.olifespan;
        }
      }
      this.geometry.__dirtyVertices = true;
    }

    return particleSystem;
  }

  var trails = ship.type ? $omega_config.resources[ship.type].trails : null;
  if(trails){
    this.trails = [];
    for(var t in trails){
      var trail  = trails[t];
      var ntrail = this.create_trail(trail[0], trail[1], trail[2])
      this.trails.push(ntrail);
      // TODO push unless stopped
      //this.components.push(ntrail);
    }
  }

  // setup attack vector
  var line_material =
    UIResources().cached('ship_attacking_material',
      function(i) {
        return new THREE.LineBasicMaterial({color: 0xFF0000 })
      });

  var particle_material =
    UIResources().cached('ship_attacking_particle_material',
      function(i) {
        return new THREE.ParticleBasicMaterial({
                     color: 0xFF0000, size: 50,
                     map: UIResources().load_texture("images/particle.png"),
                     blending: THREE.AdditiveBlending, transparent: true });
      });

  this.refresh_attack_particles = function(geo, target_loc){
    var dist = this.location.distance_from(target_loc.x,
                                           target_loc.y,
                                           target_loc.z);
    var dx = Math.abs(this.location.x - target_loc.x);
    var dy = Math.abs(this.location.y - target_loc.y);
    var dz = Math.abs(this.location.z - target_loc.z);

    // 5 unit particle + 25 unit spacer
    var num = dist / 30;
    geo.scalex = 30 / dist * dx;
    geo.scaley = 30 / dist * dy;
    geo.scalez = 30 / dist * dz;

    for(var i = 0; i < num; ++i){
      var vert = new THREE.Vector3(this.location.x + i * geo.scalex,
                                   this.location.y + i * geo.scaley,
                                   this.location.z + i * geo.scalez);
      if(geo.vertices.length > i)
        geo.vertices[i] = vert;
      else
        geo.vertices.push(vert);
    }
  }

  var particle_geo =
    UIResources().cached('ship_' + this.id + '_attacking_particle_geometry',
      function(i) {
        var geo = new THREE.Geometry();
        if(ship.attacking){
          ship.refresh_attack_particles(geo, ship.attacking.location);
        }
        return geo;
      });

  this.attack_particles =
    UIResources().cached('ship_' + this.id + '_attacking_particle_system',
      function(i){
        var particleSystem =
          new THREE.ParticleSystem(particle_geo,
                                   particle_material);
        particleSystem.position.x = ship.location.x;
        particleSystem.position.y = ship.location.y;
        particleSystem.position.z = ship.location.z;
        particleSystem.sortParticles = true;

        particleSystem.update_particles = function(){
          for(var p in this.geometry.vertices){
            var v = this.geometry.vertices[p];
            var s = Math.random();
            v.x += this.geometry.scalex + s;
            v.y += this.geometry.scaley + s;
            v.z += this.geometry.scalez + s;
            v.num += 1;

            if(ship.attacking.location.distance_from(v.x, v.y, v.z) < 30){
              v.x = ship.location.x;
              v.y = ship.location.y;
              v.z = ship.location.z;
            }
          }
          this.geometry.__dirtyVertices = true;
        };

        return particleSystem;
      });

  var line_material =
    UIResources().cached('ship_mining_material',
      function(i) {
        return new THREE.LineBasicMaterial({color: 0x0000FF});
      });

  this.mining_line_geo =
    UIResources().cached('ship_'+this.id+'_mining_geometry',
                         function(i) {
                           var geometry = new THREE.Geometry();
                           var av = ship.mining && ship.mining.entity ?
                                    ship.mining.entity.location : {x:0, y:0, z:0};
                           geometry.vertices.push(new THREE.Vector3(ship.location.x,
                                                                    ship.location.y,
                                                                    ship.location.z));
                           geometry.vertices.push(new THREE.Vector3(av[0], av[1], av[2]));

                           return geometry;
                         });
  this.mining_line =
    UIResources().cached('ship_'+this.id+'_mining_line',
                         function(i) {
                           var line = new THREE.Line(ship.mining_line_geo, line_material);
                           return line;
                         });


  // draw attack vector if attacking
  if(this.attacking){
    this.components.push(this.attack_particles);
  }

  // draw mining vector if mining
  else if(this.mining)
    this.components.push(this.mining_line);

  // some text to render in details box on click
  this.details = function(){
    var details = ['Ship: ' + this.id + '<br/>',
                   '@ ' + this.location.to_s() + '<br/>',
                   "Resources: <br/>"];
    for(var r in this.resources){
      var res = this.resources[r];
      details.push(res.quantity + " of " + res.material_id + "<br/>")
    }

    if(this.belongs_to_current_user()){
      details.push("<span id='cmd_move_select' class='commands'>move</span>");
      details.push("<span id='cmd_attack_select' class='commands'>attack</span>");
      var dcss = this.docked_at ? 'display: none' : '';
      var ucss = this.docked_at ? '' : 'display: none';
      details.push("<span id='cmd_dock_select' class='commands' style='" + dcss + "'>dock</span>");
      details.push("<span id='cmd_undock' class='commands' style='" + ucss + "'>undock</span>");
      details.push("<span id='cmd_transfer' class='commands' style='" + ucss + "'>transfer</span>");
      details.push("<span id='cmd_mine_select' class='commands'>mine</span>");
    }

    return details;
  }

  // text to render in popup on selection command click
  this.selection =
    { 'cmd_move_select' :
        ['Move Ship',
         function(){
          // coordinate specification
          return "<div class='dialog_row'>" + this.id + "</div>" +
                 "<div class='dialog_row'>X: <input id='dest_x' type='text' value='"+roundTo(this.location.x,2)+"'/></div>" +
                 "<div class='dialog_row'>Y: <input id='dest_y' type='text' value='"+roundTo(this.location.y,2)+"'/></div>" +
                 "<div class='dialog_row'>Z: <input id='dest_z' type='text' value='"+roundTo(this.location.z,2)+"'/></div>" +
                 "<div class='dialog_row'><input type='button' value='move' id='cmd_move' /></div>";
         }] ,

      'cmd_attack_select' :
        ['Launch Attack',
         function(){
          // load attack target selection from ships in the vicinity
          var entities = Entities().select(function(e) {
            return e.json_class == 'Manufactured::Ship'            &&
                   e.user_id    != Session.current_session.user_id &&
                   e.hp > 0 &&
                   e.location.is_within(ship.attack_distance, ship.location);
          });

          var text = "Select " + this.id + " target<br/>";
          for(var e in entities){
            var entity = entities[e];
            text += '<span id="cmd_attack_'+entity.id+'" class="cmd_attack dialog_cmds">' + entity.id + '</span>';
          }
          return text;
        }],

      'cmd_dock_select' :
        ['Dock Ship',
         function(){
          // load dock target selection from stations in the vicinity
          var entities = Entities().select(function(e) {
            return e.json_class == 'Manufactured::Station' &&
                   e.belongs_to_current_user() &&
                   e.location.is_within(100, ship.location);
          });

          var text = 'Dock ' + this.id + ' at<br/>';
          for(var e in entities){
            var entity = entities[e];
            text += '<span id="cmd_dock_' + entity.id + '" class="cmd_dock dialog_cmds">' + entity.id + '</span>';
          }
          return text;
        }],

      'cmd_mine_select' :
        ['Start Mining',
         function(){
          return "Select resource to mine with "+ ship.id +" <br/>";
        }]
    };

  /* added_to scene callback
   */
  this.added_to = function(scene){
    this.current_scene = scene;
  }

  /* clicked_in scene callback
   */
  this.clicked_in = function(scene){
    // remove existing command page element handlers
    // XXX should be exact same selectors as w/ live handlers below:
    $('#cmd_move_select,#cmd_attack_select,' +
      '#cmd_dock_select,#cmd_mine_select').die();
    $('#cmd_move').die()
    $('.cmd_attack').die()
    $('.cmd_dock').die();
    $('#cmd_undock').die();
    $('#cmd_transfer').die();
    $('.cmd_mine').die();

    // wire up selection command page elements,
    $('#cmd_move_select,#cmd_attack_select,' +
      '#cmd_dock_select,#cmd_mine_select').
        live('click', function(e){
          // just raise the corresponding event w/ content to display,
          // up to another component to take this and render it
          var cmd     = e.target.id;
          var cmds    = ship.selection[cmd];
          var title   = cmds[0];
          var content = cmds[1].apply(ship)
          ship.raise_event(cmd, ship, title, content);
        });

    // wire up command page elements
    $('#cmd_move').live('click', function(e){
      Commands.move_ship(ship,
                         $('#dest_x').val(),
                         $('#dest_y').val(),
                         $('#dest_z').val(),
                         function(res){
                           ship.raise_event('cmd_move', ship);
                         });
    })

    $('.cmd_attack').live('click', function(e){
      var eid = e.currentTarget.id.substr(11);
      var entity = Entities().get(eid);
      Commands.launch_attack(ship, entity,
                             function(res){
                               ship.raise_event('cmd_attack', ship, entity);
                             });
    })

    $('.cmd_dock').live('click', function(e){
      var eid = e.currentTarget.id.substr(9);
      var entity = Entities().get(eid);
      Commands.dock_ship(ship, entity,
                         function(res){
                           ship.update(res.result)
                           ship.raise_event('cmd_dock', ship, entity)
                         });
      $('#cmd_dock_select').hide();
      $('#cmd_undock').show();
      $('#cmd_transfer').show();
    })

    $('#cmd_undock').live('click', function(e){
      Commands.undock_ship(ship,
                           function(res){
                             ship.update(res.result)
                             ship.raise_event('cmd_undock', ship);
                           });
      $('#cmd_dock_select').show();
      $('#cmd_undock').hide();
      $('#cmd_transfer').hide();
    })

    $('#cmd_transfer').live('click', function(e){
      Commands.transfer_resources(ship, ship.docked_at.id,
                                  function(res){
                                    if(!res.error){
                                      var sh = res.result[0];
                                      var st = res.result[1];
                                      ship.raise_event('cmd_transfer', sh, st);
                                    }
                                  });
    })

    $('.cmd_mine').live('click', function(e){
      var rsid = e.currentTarget.id.substr(9);
      Commands.start_mining(ship, rsid,
                            function(res){
                              ship.raise_event('cmd_mine', ship, rsid);
                            });
    })

    // toggle selected
    this.selected = true;

    // refresh the ship
    this.refresh();

    // reload ship in scene
    scene.reload_entity(this);
  }

  /* unselected in scene callback
   */
  this.unselected_in = function(scene){
    this.selected = false;
    this.refresh(); // refresh ship components
    scene.reload_entity(this);
  }

  /* removed_from scene callback
   */
  this.removed_from = function(scene){
    this.current_scene = null;
  }
}

/* Return ship w/ the specified id
 */
Ship.with_id = function(id, cb){
  Entities().node().web_request('manufactured::get_entity', 'with_id', id, function(res){
    if(res.result){
      var ship = new Ship(res.result);
      cb.apply(null, [ship]);
    }
  });
};

/* Return ships owned by the specified user
 */
Ship.owned_by = function(user_id, cb){
  Entities().node().web_request('manufactured::get_entities',
                                'of_type', 'Manufactured::Ship',
                                'owned_by', user_id, function(res){
    if(res.result){
      var ships = [];
      for(var e in res.result){
        ships.push(new Ship(res.result[e]));
      }
      cb.apply(null, [ships])
    }
  });
}
