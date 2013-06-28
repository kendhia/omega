# Station module tests
#
# Copyright (C) 2012 Mohammed Morsi <mo@morsi.org>
# Licensed under the AGPLv3+ http://www.gnu.org/licenses/agpl.txt

require 'spec_helper'
require 'manufactured/station'
require 'cosmos/entities/solar_system'

module Manufactured
describe Station do
  describe "#type" do
    it "sets type" do
      s = Station.new
      s.type = :frigate
      s.type.should == :frigate
    end

    it "converts type" do
      s = Station.new
      s.type = 'offense'
      s.type.should == :offense
    end

    it "does not convert invalid type" do
      s = Station.new
      s.type = 'foobar'
      s.type.should == nil
    end

    it "sets size" do
      s = Station.new
      s.type = :offense
      s.size.should == Station::SIZES[:offense]
    end
  end

  describe "#initialize" do
    it "sets defaults" do
      s = Station.new
      s.id.should be_nil
      s.user_id.should be_nil
      s.type.should be_nil
      s.callbacks.should == []
      s.resources.should == []
      s.solar_system.should be_nil
      s.system_id.should be_nil
      s.docking_distance.should == 100
      s.cargo_capacity.should == 10000
      s.transfer_distance.should == 100
      s.construction_distance.should == 50

      s.location.should be_an_instance_of(Motel::Location)
      s.location.coordinates.should == [0,0,1]
      s.location.orientation.should == [1,0,0]
    end

    it "sets attributes" do
      r = build(:resource)
      sys = build(:solar_system)
      l = build(:location)
      s = Station.new :id                  => 'ship1',
                   :user_id             => 'user1',
                   :type                => 'manufacturing',
                   :callbacks           => [ :foo , :bar ],
                   :resources           => [r],
                   :solar_system        => sys,
                   :location            =>   l,
                   :cargo_capacity      => 500,
                   :transfer_distance   => 100,
                   :construction_distance => 200

      s.id.should == 'ship1'
      s.user_id.should == 'user1'
      s.type.should == :manufacturing
      s.callbacks.should == [:foo, :bar]
      s.resources.should == [r]
      s.solar_system.should == sys
      s.system_id.should == sys.id
      s.location.should == l
      s.cargo_capacity.should == 500
      s.transfer_distance.should == 100
      s.construction_distance.should == 200
    end
  end

  describe "#valid?" do
    before(:each) do
      @sys = build(:solar_system)
      @s   = Station.new :id           => 'ship1',
                         :user_id      => 'tu',
                         :solar_system => @sys,
                         :type         => :defense
    end

    it "returns true" do
      @s.should be_valid
    end
    
    context "id is invalid" do
      it "returns false" do
        @s.id = nil
        @s.should_not be_valid
      end
    end

    context "location is invalid" do
      it "returns false" do
        @s.location = nil
        @s.should_not be_valid
      end
    end

    context "user_id is invalid" do
      it "returns false" do
        @s.user_id = nil
        @s.should_not be_valid
      end
    end

    context "type is invalid" do
      it "returns false" do
        @s.type = 'fooz'
        @s.should_not be_valid

        @s.type = nil
        @s.should_not be_valid
      end
    end

    context "type is invalid" do
      it "returns false" do
        @s.type = nil
        @s.should_not be_valid
      end
    end

    context "size is invalid" do
      it "returns false" do
        @s.size = 512
        @s.should_not be_valid
      end
    end

    context "resources are invalid" do
      it "returns false" do
        @s.resources = ['false']
        @s.should_not be_valid
      end
    end
  end

  describe "#dockable?" do
    before(:each) do
      @s  = build(:solar_system)
      @s1 = build(:solar_system)
      @sh = Manufactured::Ship.new :id => 'ship1'
      @st = Manufactured::Station.new :id => 'station1'

      @s.location.coordinates = [0, 0, 0]
      @s1.location.coordinates = [0, 0, 1]
      @sh.location.parent = @s1.location
      @st.location.parent = @s1.location
    end

    context "ship/station in different systems" do
      it "returns false" do
        @sh.location.parent = @s.location
        @st.dockable?(@sh).should be_false
      end
    end

    context "ship/station too far away" do
      it "returns false" do
        @sh.location.x = 500
        @st.dockable?(@sh).should be_false
      end
    end

    it "returns true" do
      @st.dockable?(@sh).should be_true
    end
  end

  describe "#can_construct" do
    context "not manufacturing station" do
      it "returns false" do
        s = Station.new :type => :offense
        s.can_construct?({:type => 'Ship'}).should be_false
      end
    end

    context "invalid type" do
      it "returns false" do
        s = Station.new :type => :manufacturing
        s.can_construct?({:type => 'foobar'}).should be_false
      end
    end

    context "construction cost too high" do
      it "returns false" do
        s = Station.new :type => :manufacturing
        s.can_construct?({:type => 'Ship'}).should be_false
      end
    end

    it "returns true" do
      s = Station.new :type => :manufacturing
      s.add_resource build(:resource, :quantity => 500)
      s.can_construct?({:entity_type => 'Ship'}).should be_true
    end
  end

  describe "#construct" do
    context "cannot construct entity" do
      it "returns nil" do
        s = Station.new
        s.should_receive(:can_construct?).with({}).and_return(false)
        s.construct({}).should be_nil
      end
    end

    it "removes resources corresponding to construction cost" do
      s = Station.new :type => :manufacturing
      s.add_resource build(:resource, :quantity => 100)
      lambda {
        s.construct({:entity_type => 'Ship'})
      }.should change{s.resources.size}.by(-1)
    end

    it "instantiates entity" do
      s = Station.new :type => :manufacturing
      s.add_resource build(:resource, :quantity => 100)
      sh = s.construct({:entity_type => 'Ship'})
      sh.should be_an_instance_of(Manufactured::Ship)
    end


    it "sets entity location parent" do
      s = Station.new :type => :manufacturing,
                      :solar_system => build(:solar_system)
      s.add_resource build(:resource, :quantity => 100)
      sh = s.construct({:entity_type => 'Ship'})
      sh.location.parent.should == s.location.parent
    end

    it "sets entity parent" do
      s = Station.new :type => :manufacturing,
                      :solar_system => build(:solar_system)
      s.add_resource build(:resource, :quantity => 100)
      sh = s.construct({:entity_type => 'Ship'})
      sh.parent.should == s.parent
    end

    context "entity too far away" do
      it "moves entity closer"
    end
  end

  describe "#to_json" do
    it "returns station in json format" do
      system1 = Cosmos::Entities::SolarSystem.new :id => 'system1'
      location= Motel::Location.new :id => 20, :y => -15
      s = Manufactured::Station.new(:id => 'station42', :user_id => 420,
                                 :type => :science,
                                 :solar_system => system1,
                                 :location => location)

      j = s.to_json
      j.should include('"json_class":"Manufactured::Station"')
      j.should include('"id":"station42"')
      j.should include('"user_id":420')
      j.should include('"type":"science"')
      j.should include('"size":20')
      j.should include('"json_class":"Motel::Location"')
      j.should include('"id":20')
      j.should include('"y":-15')
      j.should include('"system_id":"system1"')
    end
  end

  describe "#json_create" do
    it "returns station from json format" do
      j = '{"json_class":"Manufactured::Station","data":{"id":"station42","user_id":420,"type":"science","size":20,"docking_distance":100,"location":{"json_class":"Motel::Location","data":{"id":20,"x":null,"y":-15.0,"z":null,"orientation_x":null,"orientation_y":null,"orientation_z":null,"restrict_view":true,"restrict_modify":true,"parent_id":null,"children":[],"movement_strategy":{"json_class":"Motel::MovementStrategies::Stopped","data":{"step_delay":1}},"callbacks":{},"last_moved_at":null}},"system_id":"system1","resources":[]}}'
      s = JSON.parse(j)

      s.class.should == Manufactured::Station
      s.id.should == "station42"
      s.user_id.should == 420
      s.type.should == :science
      s.size.should == 20
      s.location.should_not be_nil
      s.location.y.should == -15
      s.system_id.should == 'system1'
    end
  end

end # describe Station
end # module Manufactured
