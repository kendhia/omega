# manufactured::create_entity,manufactured::construct_entity tests
#
# Copyright (C) 2013 Mohammed Morsi <mo@morsi.org>
# Licensed under the AGPLv3+ http://www.gnu.org/licenses/agpl.txt

require 'spec_helper'
require 'manufactured/rjr/create'
require 'rjr/dispatcher'

module Manufactured::RJR
  describe "#create_entity" do
    include Omega::Server::DSL # for with_id below

    before(:each) do
      setup_manufactured  :CREATE_METHODS
    end

    def build_ship
      sys = create(:solar_system)
      s = build(:valid_ship)
      s.user_id = @login_user.id
      s.solar_system = sys
      s
    end

    context "insufficient privileges (create-manufactured_entities)" do
      it "raises PermissionError" do
        s = build_ship
        lambda {
          @s.create_entity(s)
        }.should raise_error(PermissionError)
      end
    end

    context "sufficient privileges (create-manufactured_entities)" do
      before(:each) do
        add_privilege(@login_role, 'create', 'manufactured_entities')
      end

      it "does not raise PermissionError" do
        s = build_ship
        lambda {
          @s.create_entity(s)
        }.should_not raise_error(PermissionError)
      end

      context "invalid entity type specified" do
        it "raises ValidationError" do
          lambda {
            @s.create_entity(42)
          }.should raise_error(ValidationError)
        end
      end

      context "invalid system specified" do
        it "raises DataNotFound" do
          sys1 = build(:solar_system)
          s = build_ship
          s.solar_system = sys1
          lambda {
            @s.create_entity(s)
          }.should raise_error(DataNotFound)
        end
      end

      context "invalid user specified" do
        it "raises DataNotFound" do
          u1 = build(:user)
          s = build_ship
          s.user_id = u1.id
          lambda {
            @s.create_entity(s)
          }.should raise_error(DataNotFound)
        end
      end

      context "user has maximum number of entities" do
        it "raises PermissionError"
      end

      [[:movement_speed,   Users::Attributes::PilotLevel.id   ],
       [:damage_dealt,     Users::Attributes::OffenseLevel.id ],
       [:max_shield_level, Users::Attributes::DefenseLevel.id ],
       [:mining_quantity,  Users::Attributes::MiningLevel.id  ]].each { |p,a|
         it "adjusts entity.#{p} from user attribute #{a}"
       }

      it "adds resource to stations"

      context "location could not be added to motel" do
        it "raises OperationError" do
          os = create(:valid_ship)
          s = build_ship
          # create_entity will set location id's the same
          s.id = os.id
          lambda {
            @s.create_entity(s)
          }.should raise_error(OperationError)
        end

        it "does not add entity"
      end

      context "entity could not be added to registry" do
        it "raises OperationError" do
          os = create(:valid_ship)
          s = build_ship
          # invalid entity:
          s.max_shield_level = 5 ; s.shield_level = 10
          lambda {
            @s.create_entity(s)
          }.should raise_error(OperationError)
        end

        it "deletes motel location"
      end

      it "creates new entity in registry" do
        s = build_ship
        lambda {
          @s.create_entity(s)
        }.should change{@registry.entities.size}.by(1)
        @registry.entity(&with_id(s.id)).should_not be_nil
      end

      it "creates new location in motel" do
        s = build_ship
        lambda {
          @s.create_entity(s)
        }.should change{Motel::RJR.registry.entities.size}.by(1)
        Motel::RJR.registry.entity(&with_id(s.location.id)).should_not be_nil
      end

      it "grants view/modify on entity to owner's role"

      it "grants view on entity's location to owner's role"

      it "returns entity" do
        s = build_ship
        r = @s.create_entity(s)
        r.should be_an_instance_of(Ship)
        r.id.should == s.id
      end
    end
  end # describe "#create_entity"

  describe "#construct_entity" do
    include Omega::Server::DSL # for with_id below

    before(:each) do
      setup_manufactured  :CREATE_METHODS
      @st = create(:valid_station)
      @construct = { :entity_type => 'Ship', :type => :frigate, :id => 'foobar' }
    end

    def build_ship
      sys = create(:solar_system)
      s = build(:valid_ship)
      s.user_id = @login_user.id
      s.solar_system = sys
      s
    end

    context "invalid manufacturer_id" do
      it "raises DataNotFound" do
        st = build(:valid_station)
        lambda {
          @s.construct_entity st.id, @construct
        }.should raise_error(DataNotFound)
      end
    end

    context "insufficient permissions (modify-manufactured_entities)" do
      it "raises PermssionError" do
        lambda {
          @s.construct_entity @st.id, @construct
        }.should raise_error(PermissionError)
      end
    end

    context "sufficient permissions (modify-manufactured_entities)" do
      before(:each) do
        add_privilege(@login_role, 'modify', 'manufactured_entities')
      end

      it "does not raise PermissionError" do
        lambda {
          @s.construct_entity @st.id, @construct
        }.should_not raise_error(PermissionError)
      end

      it "filters all properties but id, type, and entity_type" do
        @registry.safe_exec { |es|
          rst = es.find(&with_id(@st.id))
          rst.should_receive(:can_construct?).
              with{ |*a|
                (a.first.keys - [:id, :type, :entity_type, :solar_system, :user_id]).should be_empty
              }.and_call_original
        }
        @s.construct_entity @st.id, @construct.merge({:resources => build(:resource)})
      end

      it "sets entity solar system" do
        r = @s.construct_entity @st.id, @construct
        r.last.system_id.should == @st.system_id
      end

      it "sets entity user id" do
        r = @s.construct_entity @st.id, @construct
        r.last.user_id.should == @login_user.id
      end

      context "station cannot construct entity" do
        it "raises OperationError" do
          @registry.safe_exec { |es|
            es.find(&with_id(@st.id)).
               should_receive(:can_construct?).and_return(false)
          }
          lambda{
            @s.construct_entity @st.id, @construct
          }.should raise_error(OperationError)
        end
      end

      it "registers new construction_complete callback with station" do
          @s.construct_entity @st.id, @construct
          @registry.safe_exec { |es|
            cbs = es.find(&with_id(@st.id)).callbacks
            cbs.size.should == 1
            cbs.first.event_type.should == :construction_complete
          }
      end

      context "on construction complete" do
        it "removes callback from station" do
          @s.construct_entity @st.id, @construct
          rs = @registry.safe_exec { |es| cbs = es.find(&with_id(@st.id)) }
          lambda {
            rs.callbacks.first.invoke
          }.should change{rs.callbacks.size}.by(-1)
        end

        it "invokes manufactured::create_entity" do
          @s.construct_entity @st.id, @construct
          Manufactured::RJR.node.should_receive(:invoke).with{ |*a|
            a[0].should == "manufactured::create_entity"
            a[1].should be_an_instance_of(Ship)
            a[1].id.should == @construct[:id]
          }
          rs = @registry.safe_exec { |es| cbs = es.find(&with_id(@st.id)) }
          rs.callbacks.first.invoke
        end
      end

      it "constructs entity" do
        @registry.safe_exec { |es|
          es.find(&with_id(@st.id)).should_receive(:construct).and_call_original
        }
        @s.construct_entity @st.id, @construct
      end

      context "entity could not be constructed" do
        it "raises OperationError" do
          @registry.safe_exec { |es|
            es.find(&with_id(@st.id)).should_receive(:construct).and_return(nil)
          }
          lambda {
            @s.construct_entity @st.id, @construct
          }.should raise_error(OperationError)
        end
      end

      it "registers new construction command with registry" do
        lambda {
          @s.construct_entity @st.id, @construct
        }.should change{@registry.entities.size}.by(1)
        @registry.entities.last.should be_an_instance_of(Manufactured::Commands::Construction)
        @registry.entities.last.id.should == "#{@st.id}-#{@construct[:id]}"
      end

      it "returns [station,entity]" do
        r = @s.construct_entity @st.id, @construct
        r.first.should be_an_instance_of(Station)
        r.first.id.should == @st.id

        r.last.should be_an_instance_of(Ship)
        r.last.id.should == @construct[:id]
      end
    end
  end # describe #construct_entity

  describe "#dispatch_manufactured_rjr_create" do
    it "adds manufactured::create_entity to dispatcher" do
      d = ::RJR::Dispatcher.new
      dispatch_manufactured_rjr_create(d)
      d.handlers.keys.should include("manufactured::create_entity")
    end

    it "adds manufactured::construct_entity to dispatcher" do
      d = ::RJR::Dispatcher.new
      dispatch_manufactured_rjr_create(d)
      d.handlers.keys.should include("manufactured::construct_entity")
    end
  end

end #module Manufactured::RJR
