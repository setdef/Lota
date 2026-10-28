// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/physics.hpp"

#include "native/binding.hpp"
#include "native/ruby.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "common/Vector.h"
#include "common/int.h"
#include "physics/box2d/Body.h"
#include "physics/box2d/ChainShape.h"
#include "physics/box2d/CircleShape.h"
#include "physics/box2d/Contact.h"
#include "physics/box2d/DistanceJoint.h"
#include "physics/box2d/EdgeShape.h"
#include "physics/box2d/FrictionJoint.h"
#include "physics/box2d/GearJoint.h"
#include "physics/box2d/Joint.h"
#include "physics/box2d/MotorJoint.h"
#include "physics/box2d/MouseJoint.h"
#include "physics/box2d/Physics.h"
#include "physics/box2d/PolygonShape.h"
#include "physics/box2d/PrismaticJoint.h"
#include "physics/box2d/PulleyJoint.h"
#include "physics/box2d/Reference.h"
#include "physics/box2d/RevoluteJoint.h"
#include "physics/box2d/RopeJoint.h"
#include "physics/box2d/Shape.h"
#include "physics/box2d/WeldJoint.h"
#include "physics/box2d/WheelJoint.h"
#include "physics/box2d/World.h"

#include <array>
#include <cstddef>
#include <initializer_list>
#include <memory>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

namespace box2d = love::physics::box2d;
using box2d::Body;
using box2d::Contact;
using box2d::Joint;
using box2d::Physics;
using box2d::Shape;
using box2d::World;

namespace {

// A Ruby value the engine keeps for the game, where LÖVE keeps a Lua
// value in a Reference (ext/lota/engine/physics.patch, Reference.h): a
// Body's, Shape's, or Joint's user data. It is a root of Ruby's garbage
// collector from when the engine takes it until the engine lets go of it,
// as a Lua reference keeps its value in the registry. The engine deletes
// it, sometimes while Ruby collects an object whose release destroys a
// World, so its destructor only unregisters the address, which allocates
// nothing.
class RubyReference final : public box2d::Reference {
public:
  explicit RubyReference(const Rice::Object &value) : root_(value) {}

  // Reference::unref: lets the value go, as luaL_unref does, so a
  // destroyed Body's user data reads as nil.
  void unref() override { root_.clear(); }

  [[nodiscard]] Rice::Object value() const { return root_.value(); }

private:
  ruby::Root root_;
};

// A Ruby callable a World calls back for its contacts, where LÖVE keeps a
// Lua function in a Reference (ext/lota/engine/physics.patch,
// Reference.h): one of World:setCallbacks's four, or the function
// World:setContactFilter takes. It holds two values: the callable the game
// set, which World:getCallbacks and getContactFilter give back exactly, and
// the Proc Lota::Physics::World made to call it, which wraps the engine's
// objects in Lota's classes and passes the callable only the arguments it
// declares (ADR 003, section 3). Both are roots of Ruby's garbage collector
// while the World holds this, as a Lua reference keeps its function in the
// registry: the World deletes it when another replaces it, and lets it go
// (unref) when the World is destroyed, as LÖVE does (World::destroy).
class RubyCallback {
public:
  // +pair+ holds the callable, then the Proc that calls it.
  explicit RubyCallback(const std::vector<Rice::Object> &pair)
      : callable_(pair.at(0)), call_(pair.at(1)) {}

  [[nodiscard]] Rice::Object callable() const { return callable_.value(); }

  void clear() {
    callable_.clear();
    call_.clear();
  }

  // Calls the Proc with +arguments+ and returns what it returns. The Proc
  // is copied to the stack first, where Ruby's collector sees it, because a
  // callback that sets the World's callbacks deletes this object while Ruby
  // runs it. A Ruby error goes on through the engine, out of World#update,
  // as a Lua error goes through it out of World:update.
  [[nodiscard]] Rice::Object call(const Rice::Array &arguments) const {
    Rice::Object call = call_.value();
    return call.vcall("call", arguments);
  }

private:
  ruby::Root callable_;
  ruby::Root call_;
};

class RubyContactFunction final : public box2d::ContactFunction {
public:
  explicit RubyContactFunction(const std::vector<Rice::Object> &pair) : callback_(pair) {}

  void unref() override { callback_.clear(); }

  [[nodiscard]] Rice::Object callable() const { return callback_.callable(); }

  // The two Shapes, the Contact, and each contact point's normal and
  // tangent impulse, as World::ContactCallback::process gives them.
  void call(Shape *a, Shape *b, Contact *contact, const float *impulses, int count) override {
    Rice::Array arguments;
    arguments.push(a, false);
    arguments.push(b, false);
    arguments.push(contact, false);
    for (const float impulse : std::span<const float>(impulses, static_cast<std::size_t>(count))) {
      arguments.push(static_cast<double>(impulse), false);
    }
    static_cast<void>(callback_.call(arguments));
  }

private:
  RubyCallback callback_;
};

class RubyContactFilter final : public box2d::ContactFilterFunction {
public:
  explicit RubyContactFilter(const std::vector<Rice::Object> &pair) : callback_(pair) {}

  void unref() override { callback_.clear(); }

  [[nodiscard]] Rice::Object callable() const { return callback_.callable(); }

  // Whether the two Shapes collide: Ruby's truth, which is Lua's
  // (luax_toboolean).
  bool call(Shape *a, Shape *b) override {
    Rice::Array arguments;
    arguments.push(a, false);
    arguments.push(b, false);
    return ruby::truthy(callback_.call(arguments));
  }

private:
  RubyCallback callback_;
};

// The callable the game set that +function+, which Lota made, holds, or
// nil when there is none.
template <typename Function, typename Engine> Rice::Object callable_of(const Engine *function) {
  const auto *ruby = dynamic_cast<const Function *>(function);
  return (ruby == nullptr) ? ruby::nil() : ruby->callable();
}

// A new Function of +given+, nil or the callable and the Proc that calls
// it, as Lota::Physics::World passes them, for the World that takes it.
template <typename Function> std::unique_ptr<Function> function_of(const Rice::Object &given) {
  if (given.is_nil()) {
    return nullptr;
  }
  return std::make_unique<Function>(ruby::elements(Rice::Array(given.value())));
}

// A new RubyReference of +value+, for the engine object that takes it.
box2d::Reference *reference_to(const Rice::Object &value) {
  return std::make_unique<RubyReference>(value).release();
}

// The value +reference+, which Lota made, holds, or nil when there is none.
Rice::Object value_of(const box2d::Reference *reference) {
  const auto *ruby = dynamic_cast<const RubyReference *>(reference);
  return (ruby == nullptr) ? ruby::nil() : ruby->value();
}

// The category bits of every category, which LÖVE's queries and rays look
// for when given none (wrap_World.cpp, luaL_optinteger(L, 5, 0xFFFF)).
constexpr love::uint16 every_category = 0xFFFF;

// The physics module, as LÖVE's instance() macro reaches it
// (wrap_Physics.cpp:51), or an error where LÖVE would find none.
Physics *physics() {
  auto *instance = love::Module::getInstance<Physics>(love::Module::M_PHYSICS);
  if (instance == nullptr) {
    throw love::Exception("Lota::Physics is not open.");
  }
  return instance;
}

// luaopen_love_physics (wrap_Physics.cpp:945-963) creates the module once;
// it then lives as long as the process, as LÖVE's lives until the game
// quits.
void open() { open_module<Physics, Physics>(love::Module::M_PHYSICS); }

bool is_open() { return love::Module::getInstance<Physics>(love::Module::M_PHYSICS) != nullptr; }

// An object a module function reads, which must be given, as LÖVE's
// luax_checktype requires; Rice passes nil as nullptr.
template <typename T> T *present(T *object) {
  if (object == nullptr) {
    ruby::raise_type_error(std::string("wrong argument type nil (expected ") + T::type.getName() +
                           ")");
  }
  return object;
}

// The checks LÖVE's luax_checkbody, luax_checkworld, and luax_checkjoint
// make of the object they read (wrap_Body.cpp:32-38, wrap_World.cpp:30-36,
// wrap_Joint.cpp:78-84), and luax_checkcontact (wrap_Contact.cpp:31-37).
void check(const Body &body) {
  if (body.body == nullptr) {
    throw love::Exception("Attempt to use destroyed body.");
  }
}

void check(const World &world) {
  if (!world.isValid()) {
    throw love::Exception("Attempt to use destroyed world.");
  }
}

void check(const Joint &joint) {
  if (!joint.isValid()) {
    throw love::Exception("Attempt to use destroyed joint.");
  }
}

// The same checks of an object a module function reads by pointer, which
// must also be given.
template <typename T> void check(T *object) { check(*present(object)); }

void check(Contact &contact) {
  if (!contact.isValid()) {
    throw love::Exception("Attempt to use destroyed contact.");
  }
}

// The numbers +values+ holds from +offset+ on, N of them, as floats, as
// LÖVE casts each Lua number it reads.
template <std::size_t N>
std::array<float, N> take(const std::vector<double> &values, std::size_t offset) {
  std::array<float, N> taken{};
  for (std::size_t i = 0; i < N; i++) {
    taken.at(i) = static_cast<float>(values.at(offset + i));
  }
  return taken;
}

// Each number of an Array, as a Lua number, a double.
std::vector<double> numbers(const Rice::Array &array) {
  std::vector<double> values;
  for (const auto item : array) {
    values.push_back(Rice::detail::From_Ruby<double>().convert(item.value()));
  }
  return values;
}

Rice::Array floats(std::initializer_list<float> values) {
  Rice::Array results;
  for (const float value : values) {
    results.push(static_cast<double>(value), false);
  }
  return results;
}

template <typename T> Rice::Array objects(const std::vector<T> &values) {
  Rice::Array results;
  for (const auto &value : values) {
    results.push(value, false);
  }
  return results;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below (vendor/love/src/modules/physics/
// box2d), and changed to take its arguments from Rice instead of a
// lua_State; where a wrap function called a method Lota's physics patch
// changed, the port calls the method as the patch leaves it.

// w_newCircleShape (wrap_Physics.cpp:307-336) with a Body, in its form with
// a position and a radius; Lota::Physics::CircleShape.new passes 0, 0 for
// the form with a radius alone, as LÖVE does.
box2d::CircleShape *new_circle_shape(Body *body, double x, double y, double radius) {
  check(body);
  return physics()->newCircleShape(body, static_cast<float>(x), static_cast<float>(y),
                                   static_cast<float>(radius));
}

// w_newRectangleShape (wrap_Physics.cpp:338-370) with a Body;
// Lota::Physics::RectangleShape.new passes 0, 0, and an angle of 0 for the
// form with a size alone, as LÖVE does.
box2d::PolygonShape *new_rectangle_shape(Body *body, Rice::Array placement_given) {
  const Rice::Array placement = std::move(placement_given);
  check(body);
  const std::vector<double> p = numbers(placement);
  const auto [x, y, w, h] = take<4>(p, 0);
  return physics()->newRectangleShape(body, x, y, w, h, static_cast<float>(p.at(4)));
}

// w_newEdgeShape (wrap_Physics.cpp:372-397) with a Body: the edge's two
// points, and its previous and next vertex when there are eight numbers.
box2d::EdgeShape *new_edge_shape(Body *body, Rice::Array coordinates_given) {
  const Rice::Array coordinates = std::move(coordinates_given);
  check(body);
  const std::vector<double> c = numbers(coordinates);
  const auto [x1, y1, x2, y2] = take<4>(c, 0);
  if (c.size() <= 4) {
    return physics()->newEdgeShape(body, x1, y1, x2, y2);
  }
  const auto [prevx, prevy, nextx, nexty] = take<4>(c, 4);
  return physics()->newEdgeShape(body, x1, y1, x2, y2, prevx, prevy, nextx, nexty);
}

// The vertices of w_newPolygonShape and w_newChainShape, from their
// coordinates as numbers (wrap_Physics.cpp:405-436 and 452-485).
std::vector<love::Vector2> vertices(const std::vector<double> &c) {
  if (c.size() % 2 != 0) {
    throw love::Exception("Number of vertex components must be a multiple of two.");
  }
  std::vector<love::Vector2> coords;
  coords.reserve(c.size() / 2);
  for (std::size_t i = 0; i < c.size() / 2; i++) {
    coords.emplace_back(static_cast<float>(c.at(2 * i)), static_cast<float>(c.at((2 * i) + 1)));
  }
  return coords;
}

// w_newPolygonShape (wrap_Physics.cpp:399-444) with a Body.
box2d::PolygonShape *new_polygon_shape(Body *body, Rice::Array coordinates_given) {
  const Rice::Array coordinates = std::move(coordinates_given);
  check(body);
  const std::vector<love::Vector2> coords = vertices(numbers(coordinates));
  return physics()->newPolygonShape(body, coords.data(), static_cast<int>(coords.size()));
}

// w_newChainShape (wrap_Physics.cpp:446-490) with a Body, which needs at
// least one vertex.
box2d::ChainShape *new_chain_shape(Body *body, bool loop, Rice::Array coordinates_given) {
  const Rice::Array coordinates = std::move(coordinates_given);
  check(body);
  const std::vector<double> c = numbers(coordinates);
  if (c.empty()) {
    throw love::Exception("Number of vertex components must be a multiple of two.");
  }
  const std::vector<love::Vector2> coords = vertices(c);
  return physics()->newChainShape(body, loop, coords.data(), static_cast<int>(coords.size()));
}

// The joints' factories (wrap_Physics.cpp:492-775), each with its numbers
// as LÖVE reads them for the form Lota::Physics's joint classes choose by
// how many there are, as LÖVE chooses by lua_gettop.
// The anchors of a revolute, friction, or weld joint: xA, yA, and xB, yB,
// which are A's when only two numbers are given.
std::array<float, 4> anchors_of(const std::vector<double> &a) {
  if (a.size() >= 4) {
    return take<4>(a, 0);
  }
  const auto [x, y] = take<2>(a, 0);
  return {x, y, x, y};
}

box2d::RevoluteJoint *new_revolute_joint(Body *body1, Body *body2, Rice::Array anchors_given,
                                         bool collide_connected,
                                         std::optional<double> reference_angle) {
  const Rice::Array anchors = std::move(anchors_given);
  check(body1);
  check(body2);
  const auto [xA, yA, xB, yB] = anchors_of(numbers(anchors));
  if (reference_angle.has_value()) {
    return physics()->newRevoluteJoint(body1, body2, xA, yA, xB, yB, collide_connected,
                                       static_cast<float>(*reference_angle));
  }
  return physics()->newRevoluteJoint(body1, body2, xA, yA, xB, yB, collide_connected);
}

box2d::FrictionJoint *new_friction_joint(Body *body1, Body *body2, Rice::Array anchors_given,
                                         bool collide_connected) {
  const Rice::Array anchors = std::move(anchors_given);
  check(body1);
  check(body2);
  const auto [xA, yA, xB, yB] = anchors_of(numbers(anchors));
  return physics()->newFrictionJoint(body1, body2, xA, yA, xB, yB, collide_connected);
}

box2d::WeldJoint *new_weld_joint(Body *body1, Body *body2, Rice::Array anchors_given,
                                 bool collide_connected, std::optional<double> reference_angle) {
  const Rice::Array anchors = std::move(anchors_given);
  check(body1);
  check(body2);
  const auto [xA, yA, xB, yB] = anchors_of(numbers(anchors));
  if (reference_angle.has_value()) {
    return physics()->newWeldJoint(body1, body2, xA, yA, xB, yB, collide_connected,
                                   static_cast<float>(*reference_angle));
  }
  return physics()->newWeldJoint(body1, body2, xA, yA, xB, yB, collide_connected);
}

// The anchors and axis of a prismatic or wheel joint: xA, yA, xB, yB, ax,
// ay, with B's anchor A's when only four numbers are given.
std::array<float, 6> axis_anchors_of(const std::vector<double> &a) {
  constexpr std::size_t both_anchors = 6;
  if (a.size() >= both_anchors) {
    return take<both_anchors>(a, 0);
  }
  const auto [x, y, ax, ay] = take<4>(a, 0);
  return {x, y, x, y, ax, ay};
}

box2d::PrismaticJoint *new_prismatic_joint(Body *body1, Body *body2, Rice::Array anchors_given,
                                           bool collide_connected,
                                           std::optional<double> reference_angle) {
  const Rice::Array anchors = std::move(anchors_given);
  check(body1);
  check(body2);
  const auto [xA, yA, xB, yB, ax, ay] = axis_anchors_of(numbers(anchors));
  if (reference_angle.has_value()) {
    return physics()->newPrismaticJoint(body1, body2, xA, yA, xB, yB, ax, ay, collide_connected,
                                        static_cast<float>(*reference_angle));
  }
  return physics()->newPrismaticJoint(body1, body2, xA, yA, xB, yB, ax, ay, collide_connected);
}

box2d::WheelJoint *new_wheel_joint(Body *body1, Body *body2, Rice::Array anchors_given,
                                   bool collide_connected) {
  const Rice::Array anchors = std::move(anchors_given);
  check(body1);
  check(body2);
  const auto [xA, yA, xB, yB, ax, ay] = axis_anchors_of(numbers(anchors));
  return physics()->newWheelJoint(body1, body2, xA, yA, xB, yB, ax, ay, collide_connected);
}

// w_getDistance (wrap_Physics.cpp:777-780), through Physics::getDistance:
// the distance between the Shapes and the two closest points.
Rice::Array distance(Shape *shape_a, Shape *shape_b) {
  float x1 = 0;
  float y1 = 0;
  float x2 = 0;
  float y2 = 0;
  const float distance = physics()->getDistance(present(shape_a), present(shape_b), x1, y1, x2, y2);
  return floats({distance, x1, y1, x2, y2});
}

// w_Body_getShapes, w_Body_getJoints, and w_Body_getContacts
// (wrap_Body.cpp:621-652): each as an Array.
Rice::Array body_shapes(const Body &body) {
  check(body);
  return objects(body.getShapes());
}

Rice::Array body_joints(const Body &body) {
  check(body);
  return objects(body.getJoints());
}

Rice::Array body_contacts(const Body &body) {
  check(body);
  Rice::Array results;
  for (const auto &contact : body.getContacts()) {
    results.push(contact.get(), false);
  }
  return results;
}

// w_Body_getMassData (wrap_Body.cpp:158-163).
Rice::Array body_mass_data(Body &body) {
  check(body);
  float x = 0;
  float y = 0;
  float mass = 0;
  float inertia = 0;
  body.getMassData(x, y, mass, inertia);
  return floats({x, y, mass, inertia});
}

// w_Body_getWorldPoints and w_Body_getLocalPoints (wrap_Body.cpp:448-453
// and 483-488), through Body::getWorldPoints and getLocalPoints: each pair
// of numbers transformed. LÖVE asks for at least two (luax_assert_argc),
// reads each as a float, and returns as many values as it was given, so an
// odd one out comes back as it was.
Rice::Array points(Body &body, const Rice::Array &coordinates,
                   void (Body::*transform)(std::vector<float> &)) {
  check(body);
  const std::vector<double> given = numbers(coordinates);
  if (given.size() < 2) {
    throw love::Exception("Expected at least 2 arguments");
  }
  std::vector<float> coords;
  coords.reserve(given.size());
  for (const double value : given) {
    coords.push_back(static_cast<float>(value));
  }
  (body.*transform)(coords);
  Rice::Array results;
  for (std::size_t i = 0; i < coords.size(); i++) {
    results.push((i == coords.size() - 1 && coords.size() % 2 != 0)
                     ? given.at(i)
                     : static_cast<double>(coords.at(i)),
                 false);
  }
  return results;
}

Rice::Array world_points(Body &body, Rice::Array coordinates_given) {
  const Rice::Array coordinates = std::move(coordinates_given);
  return points(body, coordinates, &Body::getWorldPoints);
}

Rice::Array local_points(Body &body, Rice::Array coordinates_given) {
  const Rice::Array coordinates = std::move(coordinates_given);
  return points(body, coordinates, &Body::getLocalPoints);
}

// w_Body_setUserData and w_Body_getUserData (wrap_Body.cpp:668-680), and
// the same for Shape (wrap_Shape.cpp:284-300) and Joint
// (wrap_Joint.cpp:140-152): any Ruby value, held as Reference.h's
// Reference.
void body_set_user_data(Body &body, Rice::Object value_given) {
  const Rice::Object value = std::move(value_given);
  check(body);
  body.setUserData(reference_to(value));
}

Rice::Object body_user_data(const Body &body) {
  check(body);
  return value_of(body.getUserData());
}

void shape_set_user_data(Shape &shape, Rice::Object value_given) {
  const Rice::Object value = std::move(value_given);
  shape.setUserData(reference_to(value));
}

Rice::Object shape_user_data(const Shape &shape) { return value_of(shape.getUserData()); }

void joint_set_user_data(Joint &joint, Rice::Object value_given) {
  const Rice::Object value = std::move(value_given);
  check(joint);
  joint.setUserData(reference_to(value));
}

Rice::Object joint_user_data(const Joint &joint) {
  check(joint);
  return value_of(joint.getUserData());
}

// w_Body_applyForce and w_Body_applyLinearImpulse (wrap_Body.cpp:220-250
// and 277-305): at the center of mass, waking the Body unless +rest+ is
// false, or at a point, with +rest+ the point and that flag. The count of
// LÖVE's arguments chooses, as lua_gettop does.
template <typename AtCenter, typename AtPoint>
void apply(Body &body, const Rice::Array &arguments, AtCenter at_center, AtPoint at_point) {
  check(body);
  const std::vector<Rice::Object> rest = ruby::elements(arguments);
  const std::size_t nargs = 3 + rest.size();
  const auto is_boolean = [&rest](std::size_t index) {
    return index < rest.size() && ruby::is_boolean(rest.at(index));
  };
  // luax_optboolean (src/common/runtime.cpp:270-275): true unless the
  // argument is true or false.
  const auto flag = [&rest, &is_boolean](std::size_t index) {
    return is_boolean(index) ? ruby::is_true(rest.at(index)) : true;
  };
  if (nargs <= 3 || (nargs == 4 && is_boolean(0))) {
    at_center(flag(0));
  } else if (constexpr std::size_t with_point = 5; nargs >= with_point) {
    const double rx = Rice::detail::From_Ruby<double>().convert(rest.at(0).value());
    const double ry = Rice::detail::From_Ruby<double>().convert(rest.at(1).value());
    at_point(static_cast<float>(rx), static_cast<float>(ry), flag(2));
  } else {
    throw love::Exception("Wrong number of parameters.");
  }
}

void apply_force(Body &body, double fx, double fy, Rice::Array rest_given) {
  const Rice::Array rest = std::move(rest_given);
  const auto x = static_cast<float>(fx);
  const auto y = static_cast<float>(fy);
  apply(
      body, rest, [&](bool awake) { body.applyForce(x, y, awake); },
      [&](float rx, float ry, bool awake) { body.applyForce(x, y, rx, ry, awake); });
}

void apply_linear_impulse(Body &body, double jx, double jy, Rice::Array rest_given) {
  const Rice::Array rest = std::move(rest_given);
  const auto x = static_cast<float>(jx);
  const auto y = static_cast<float>(jy);
  apply(
      body, rest, [&](bool awake) { body.applyLinearImpulse(x, y, awake); },
      [&](float rx, float ry, bool awake) { body.applyLinearImpulse(x, y, rx, ry, awake); });
}

// w_World_update (wrap_World.cpp:38-56): one step of +dt+ seconds, with
// Box2D 2.3's eight velocity and three position iterations unless both are
// given. LÖVE first points the World's callbacks at the calling Lua thread
// (World::setCallbacksL), which Ruby has no need of. A Ruby error a contact
// callback raises leaves the step where it is raised, as a Lua error does,
// and Rice raises it again here.
void world_update(World &world, double dt, std::optional<int> velocityiterations,
                  std::optional<int> positioniterations) {
  check(world);
  if (!velocityiterations.has_value()) {
    world.update(static_cast<float>(dt));
  } else {
    world.update(static_cast<float>(dt), *velocityiterations,
                 required(positioniterations, "positioniterations"));
  }
}

// w_World_setCallbacks and w_World_getCallbacks (wrap_World.cpp:58-70),
// through World::setCallbacks and getCallbacks as Lota's physics patch
// leaves them: begin, end, presolve, and postsolve, each nil or the
// callable and the Proc that calls it. LÖVE checks that each is a function
// before it changes any; Lota::Physics::World#callbacks= checks that each
// answers call.
void set_callbacks(World &world, Rice::Array functions_given) {
  const Rice::Array functions = std::move(functions_given);
  check(world);
  const std::vector<Rice::Object> given = ruby::elements(functions);
  std::array<std::unique_ptr<RubyContactFunction>, 4> made;
  for (std::size_t i = 0; i < made.size(); i++) {
    made.at(i) = function_of<RubyContactFunction>(i < given.size() ? given.at(i) : ruby::nil());
  }
  world.setCallbacks(made.at(0).release(), made.at(1).release(), made.at(2).release(),
                     made.at(3).release());
}

Rice::Array callbacks(World &world) {
  check(world);
  std::array<box2d::ContactFunction *, 4> functions{};
  world.getCallbacks(functions.at(0), functions.at(1), functions.at(2), functions.at(3));
  Rice::Array results;
  for (const box2d::ContactFunction *function : functions) {
    results.push(callable_of<RubyContactFunction>(function), false);
  }
  return results;
}

// w_World_setContactFilter and w_World_getContactFilter
// (wrap_World.cpp:72-84), through World::setContactFilter and
// getContactFilter: nil, or the callable and the Proc that calls it.
void set_contact_filter(World &world, Rice::Object filter_given) {
  const Rice::Object filter = std::move(filter_given);
  check(world);
  world.setContactFilter(function_of<RubyContactFilter>(filter).release());
}

Rice::Object contact_filter(World &world) {
  check(world);
  return callable_of<RubyContactFilter>(world.getContactFilter());
}

// w_World_getBodies, getJoints, and getContacts (wrap_World.cpp:154-179).
Rice::Array world_bodies(const World &world) {
  check(world);
  return objects(world.getBodies());
}

Rice::Array world_joints(const World &world) {
  check(world);
  return objects(world.getJoints());
}

Rice::Array world_contacts(World &world) {
  check(world);
  Rice::Array results;
  for (const auto &contact : world.getContacts()) {
    results.push(contact.get(), false);
  }
  return results;
}

// w_World_getGravity (wrap_World.cpp:95-100).
Rice::Array world_gravity(const World &world) {
  check(world);
  float x = 0;
  float y = 0;
  world.getGravity(x, y);
  return floats({x, y});
}

// w_World_getShapesInArea (wrap_World.cpp:194-201): every Shape whose
// bounding box overlaps the area, of the categories in +mask+, all by
// default (0xFFFF).
Rice::Array shapes_in_area(World &world, double lx, double ly, double ux, double uy,
                           std::optional<long long> mask) {
  check(world);
  return objects(world.getShapesInArea(static_cast<float>(lx), static_cast<float>(ly),
                                       static_cast<float>(ux), static_cast<float>(uy),
                                       static_cast<love::uint16>(mask.value_or(every_category))));
}

// The block World:queryShapesInArea and World:rayCast call, as LÖVE calls
// its function there (World.cpp, QueryCallback and RayCastCallback): with
// the Shape, what else the World passes, and the arguments after the
// function, which LÖVE passes on to it.
class BlockQuery final : public box2d::QueryFunction {
public:
  BlockQuery(Rice::Object block, std::vector<Rice::Object> arguments)
      : block_(std::move(block)), arguments_(std::move(arguments)) {}

  // Whether to go on: Ruby's truth, which is Lua's (luax_toboolean).
  bool call(Shape *shape) override {
    Rice::Array arguments;
    arguments.push(shape, false);
    for (const Rice::Object &argument : arguments_) {
      arguments.push(argument, false);
    }
    return ruby::truthy(block_.vcall("call", arguments));
  }

private:
  Rice::Object block_;
  std::vector<Rice::Object> arguments_;
};

class BlockRayCast final : public box2d::RayCastFunction {
public:
  BlockRayCast(Rice::Object block, std::vector<Rice::Object> arguments)
      : block_(std::move(block)), arguments_(std::move(arguments)) {}

  // The fraction to clip the ray to, which must be a number.
  float call(Shape *shape, float x, float y, float xn, float yn, float fraction) override {
    Rice::Array arguments;
    arguments.push(shape, false);
    for (const float value : {x, y, xn, yn, fraction}) {
      arguments.push(static_cast<double>(value), false);
    }
    for (const Rice::Object &argument : arguments_) {
      arguments.push(argument, false);
    }
    const Rice::Object result = block_.vcall("call", arguments);
    if (!ruby::is_numeric(result)) {
      throw love::Exception("Raycast callback didn't return a number!");
    }
    return static_cast<float>(Rice::detail::From_Ruby<double>().convert(result.value()));
  }

private:
  Rice::Object block_;
  std::vector<Rice::Object> arguments_;
};

// w_World_queryShapesInArea (wrap_World.cpp:181-186), with +call+ the
// block, as a Proc, and then the arguments to pass on to it, which
// Lota::Physics::World#query_shapes_in_area gathers into one Array.
void query_shapes_in_area(World &world, double lx, double ly, double ux, double uy,
                          Rice::Array call_given) {
  const Rice::Array call = std::move(call_given);
  check(world);
  std::vector<Rice::Object> arguments = ruby::elements(call);
  const Rice::Object block = arguments.empty() ? ruby::nil() : arguments.front();
  if (block.is_nil()) {
    ruby::raise_argument_error("no block given");
  }
  arguments.erase(arguments.begin());
  BlockQuery query(block, std::move(arguments));
  world.queryShapesInArea(static_cast<float>(lx), static_cast<float>(ly), static_cast<float>(ux),
                          static_cast<float>(uy), &query);
}

// w_World_rayCast (wrap_World.cpp:203-210), with +call+ as
// query_shapes_in_area takes it.
void ray_cast(World &world, double x1, double y1, double x2, double y2, Rice::Array call_given) {
  const Rice::Array call = std::move(call_given);
  check(world);
  std::vector<Rice::Object> arguments = ruby::elements(call);
  const Rice::Object block = arguments.empty() ? ruby::nil() : arguments.front();
  if (block.is_nil()) {
    ruby::raise_argument_error("no block given");
  }
  arguments.erase(arguments.begin());
  BlockRayCast raycast(block, std::move(arguments));
  world.rayCast(static_cast<float>(x1), static_cast<float>(y1), static_cast<float>(x2),
                static_cast<float>(y2), &raycast);
}

// w_World_rayCastAny and w_World_rayCastClosest (wrap_World.cpp:212-228):
// the Shape hit, the point, the normal, and the fraction, or none, as an
// empty Array (ADR 001, rule 4).
Rice::Array ray_cast_one(World &world, double x1, double y1, double x2, double y2,
                         std::optional<long long> mask, bool any) {
  check(world);
  float x = 0;
  float y = 0;
  float xn = 0;
  float yn = 0;
  float fraction = 0;
  const auto bits = static_cast<love::uint16>(mask.value_or(every_category));
  const auto [fx1, fy1, fx2, fy2] = std::array<float, 4>{
      static_cast<float>(x1),
      static_cast<float>(y1),
      static_cast<float>(x2),
      static_cast<float>(y2),
  };
  Shape *shape = any ? world.rayCastAny(fx1, fy1, fx2, fy2, bits, x, y, xn, yn, fraction)
                     : world.rayCastClosest(fx1, fy1, fx2, fy2, bits, x, y, xn, yn, fraction);
  Rice::Array results;
  if (shape != nullptr) {
    results.push(shape, false);
    for (const float value : {x, y, xn, yn, fraction}) {
      results.push(static_cast<double>(value), false);
    }
  }
  return results;
}

Rice::Array ray_cast_any(World &world, double x1, double y1, double x2, double y2,
                         std::optional<long long> mask) {
  return ray_cast_one(world, x1, y1, x2, y2, mask, true);
}

Rice::Array ray_cast_closest(World &world, double x1, double y1, double x2, double y2,
                             std::optional<long long> mask) {
  return ray_cast_one(world, x1, y1, x2, y2, mask, false);
}

// w_Shape_setCategory, getCategory, setMask, and getMask
// (wrap_Shape.cpp:248-282): categories counting from 1, read from the
// Array of every argument, or the Array that is the first.
std::vector<int> bit_list(const Rice::Array &given) {
  std::vector<Rice::Object> values = ruby::elements(given);
  if (!values.empty() && ruby::is_array(values.front())) {
    values = ruby::elements(Rice::Array(values.front().value()));
  }
  std::vector<int> list;
  list.reserve(values.size());
  for (const Rice::Object &value : values) {
    list.push_back(Rice::detail::From_Ruby<int>().convert(value.value()));
  }
  return list;
}

Rice::Array integers(const std::vector<int> &values) {
  Rice::Array results;
  for (const int value : values) {
    results.push(value, false);
  }
  return results;
}

void set_category(Shape &shape, Rice::Array categories_given) {
  const Rice::Array categories = std::move(categories_given);
  shape.setCategory(bit_list(categories));
}

Rice::Array category(Shape &shape) { return integers(shape.getCategory()); }

void set_mask(Shape &shape, Rice::Array masks_given) {
  const Rice::Array masks = std::move(masks_given);
  shape.setMask(bit_list(masks));
}

Rice::Array mask(Shape &shape) { return integers(shape.getMask()); }

// w_Shape_computeAABB, getBoundingBox, computeMass, and getMassData
// (wrap_Shape.cpp:208-318), through the Shape's methods as the patch
// leaves them; a child counts from 1.
Rice::Array compute_aabb(const Shape &shape, double x, double y, double r, int child_index) {
  float lx = 0;
  float ly = 0;
  float ux = 0;
  float uy = 0;
  shape.computeAABB(static_cast<float>(x), static_cast<float>(y), static_cast<float>(r),
                    child_index, lx, ly, ux, uy);
  return floats({lx, ly, ux, uy});
}

Rice::Array bounding_box(const Shape &shape, int child_index) {
  float lx = 0;
  float ly = 0;
  float ux = 0;
  float uy = 0;
  shape.getBoundingBox(child_index, lx, ly, ux, uy);
  return floats({lx, ly, ux, uy});
}

Rice::Array compute_mass(const Shape &shape, double density) {
  float x = 0;
  float y = 0;
  float mass = 0;
  float inertia = 0;
  shape.computeMass(static_cast<float>(density), x, y, mass, inertia);
  return floats({x, y, mass, inertia});
}

Rice::Array shape_mass_data(const Shape &shape) {
  float x = 0;
  float y = 0;
  float mass = 0;
  float inertia = 0;
  shape.getMassData(x, y, mass, inertia);
  return floats({x, y, mass, inertia});
}

// w_Shape_rayCast (wrap_Shape.cpp:199-206), through Shape::rayCast: the
// ray's two points and how far along it to look, then a child (from 1),
// or the Shape's position and angle and then a child, as LÖVE chooses by
// whether its seventh argument is given. The hit's normal and fraction, or
// none, as an empty Array.
Rice::Array shape_ray_cast(const Shape &shape, Rice::Array ray_given, Rice::Array rest_given) {
  const Rice::Array ray = std::move(ray_given);
  const Rice::Array rest = std::move(rest_given);
  const std::vector<double> r = numbers(ray);
  const std::vector<double> more = numbers(rest);
  const auto [p1x, p1y, p2x, p2y] = take<4>(r, 0);
  const auto max_fraction = static_cast<float>(r.at(4));
  float xn = 0;
  float yn = 0;
  float fraction = 0;
  bool hit = false;
  if (more.size() < 2) {
    const int child = more.empty() ? 1 : static_cast<int>(more.at(0));
    hit = shape.rayCast(p1x, p1y, p2x, p2y, max_fraction, nullptr, child, xn, yn, fraction);
  } else {
    if (more.size() < 3) {
      throw std::invalid_argument("Missing argument. Name: r.");
    }
    const std::array<float, 3> transform = take<3>(more, 0);
    const int child = (more.size() > 3) ? static_cast<int>(more.at(3)) : 1;
    hit =
        shape.rayCast(p1x, p1y, p2x, p2y, max_fraction, transform.data(), child, xn, yn, fraction);
  }
  return hit ? floats({xn, yn, fraction}) : Rice::Array();
}

// w_Joint_getAnchors and w_Joint_getReactionForce (wrap_Joint.cpp:111-123).
Rice::Array anchors(Joint &joint) {
  check(joint);
  float x1 = 0;
  float y1 = 0;
  float x2 = 0;
  float y2 = 0;
  joint.getAnchors(x1, y1, x2, y2);
  return floats({x1, y1, x2, y2});
}

Rice::Array reaction_force(Joint &joint, double dt) {
  check(joint);
  float x = 0;
  float y = 0;
  joint.getReactionForce(static_cast<float>(dt), x, y);
  return floats({x, y});
}

// w_Contact_getNormal and getPositions (wrap_Contact.cpp:39-49).
Rice::Array normal(Contact &contact) {
  check(contact);
  float x = 0;
  float y = 0;
  contact.getNormal(x, y);
  return floats({x, y});
}

Rice::Array positions(Contact &contact) {
  check(contact);
  Rice::Array results;
  for (const float value : contact.getPositions()) {
    results.push(static_cast<double>(value), false);
  }
  return results;
}

// SPDX-SnippetEnd

} // namespace

void define_physics(const Rice::Module &native) {
  // Their other methods are generated (ext/lota/native/generated/physics.cpp).
  define_engine_class<World>(native, "World")
      .define_method("update", &world_update, Rice::Arg("dt"),
                     Rice::Arg("velocityiterations") = std::optional<int>(),
                     Rice::Arg("positioniterations") = std::optional<int>())
      .define_method("set_callbacks", &set_callbacks, Rice::Arg("functions"))
      .define_method("callbacks", &callbacks)
      .define_method("set_contact_filter", &set_contact_filter, Rice::Arg("filter"))
      .define_method("contact_filter", &contact_filter)
      .define_method("bodies", &world_bodies)
      .define_method("joints", &world_joints)
      .define_method("contacts", &world_contacts)
      .define_method("gravity", &world_gravity)
      .define_method("shapes_in_area", &shapes_in_area, Rice::Arg("lx"), Rice::Arg("ly"),
                     Rice::Arg("ux"), Rice::Arg("uy"),
                     Rice::Arg("mask") = std::optional<long long>())
      .define_method("query_shapes_in_area", &query_shapes_in_area, Rice::Arg("lx"),
                     Rice::Arg("ly"), Rice::Arg("ux"), Rice::Arg("uy"), Rice::Arg("call"))
      .define_method("ray_cast", &ray_cast, Rice::Arg("x1"), Rice::Arg("y1"), Rice::Arg("x2"),
                     Rice::Arg("y2"), Rice::Arg("call"))
      .define_method("ray_cast_any", &ray_cast_any, Rice::Arg("x1"), Rice::Arg("y1"),
                     Rice::Arg("x2"), Rice::Arg("y2"),
                     Rice::Arg("mask") = std::optional<long long>())
      .define_method("ray_cast_closest", &ray_cast_closest, Rice::Arg("x1"), Rice::Arg("y1"),
                     Rice::Arg("x2"), Rice::Arg("y2"),
                     Rice::Arg("mask") = std::optional<long long>());

  define_engine_class<Body>(native, "Body")
      .define_method("shapes", &body_shapes)
      .define_method("joints", &body_joints)
      .define_method("contacts", &body_contacts)
      .define_method("mass_data", &body_mass_data)
      .define_method("world_points", &world_points, Rice::Arg("coordinates"))
      .define_method("local_points", &local_points, Rice::Arg("coordinates"))
      .define_method("set_user_data", &body_set_user_data, Rice::Arg("value"))
      .define_method("user_data", &body_user_data)
      .define_method("apply_force", &apply_force, Rice::Arg("fx"), Rice::Arg("fy"),
                     Rice::Arg("rest"))
      .define_method("apply_linear_impulse", &apply_linear_impulse, Rice::Arg("jx"),
                     Rice::Arg("jy"), Rice::Arg("rest"));

  define_engine_class<Shape>(native, "Shape")
      .define_method("set_category", &set_category, Rice::Arg("categories"))
      .define_method("category", &category)
      .define_method("set_mask", &set_mask, Rice::Arg("masks"))
      .define_method("mask", &mask)
      .define_method("compute_aabb", &compute_aabb, Rice::Arg("x"), Rice::Arg("y"), Rice::Arg("r"),
                     Rice::Arg("child_index") = 1)
      .define_method("bounding_box", &bounding_box, Rice::Arg("child_index") = 1)
      .define_method("compute_mass", &compute_mass, Rice::Arg("density"))
      .define_method("mass_data", &shape_mass_data)
      .define_method("ray_cast", &shape_ray_cast, Rice::Arg("ray"), Rice::Arg("rest"))
      .define_method("set_user_data", &shape_set_user_data, Rice::Arg("value"))
      .define_method("user_data", &shape_user_data);
  define_engine_class<box2d::CircleShape, Shape>(native, "CircleShape");
  define_engine_class<box2d::PolygonShape, Shape>(native, "PolygonShape");
  define_engine_class<box2d::EdgeShape, Shape>(native, "EdgeShape");
  define_engine_class<box2d::ChainShape, Shape>(native, "ChainShape");

  define_engine_class<Joint>(native, "Joint")
      .define_method("anchors", &anchors)
      .define_method("reaction_force", &reaction_force, Rice::Arg("dt"))
      .define_method("set_user_data", &joint_set_user_data, Rice::Arg("value"))
      .define_method("user_data", &joint_user_data);
  define_engine_class<box2d::DistanceJoint, Joint>(native, "DistanceJoint");
  define_engine_class<box2d::FrictionJoint, Joint>(native, "FrictionJoint");
  define_engine_class<box2d::GearJoint, Joint>(native, "GearJoint");
  define_engine_class<box2d::MotorJoint, Joint>(native, "MotorJoint");
  define_engine_class<box2d::MouseJoint, Joint>(native, "MouseJoint");
  define_engine_class<box2d::PrismaticJoint, Joint>(native, "PrismaticJoint");
  define_engine_class<box2d::PulleyJoint, Joint>(native, "PulleyJoint");
  define_engine_class<box2d::RevoluteJoint, Joint>(native, "RevoluteJoint");
  define_engine_class<box2d::RopeJoint, Joint>(native, "RopeJoint");
  define_engine_class<box2d::WeldJoint, Joint>(native, "WeldJoint");
  define_engine_class<box2d::WheelJoint, Joint>(native, "WheelJoint");

  define_engine_class<Contact>(native, "Contact")
      .define_method("normal", &normal)
      .define_method("positions", &positions);

  const Rice::Return owned = Rice::Return().takeOwnership();
  Rice::define_module_under(native, "Physics")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("new_circle_shape", &new_circle_shape, Rice::Arg("body"),
                                 Rice::Arg("x"), Rice::Arg("y"), Rice::Arg("radius"), owned)
      .define_singleton_function("new_rectangle_shape", &new_rectangle_shape, Rice::Arg("body"),
                                 Rice::Arg("placement"), owned)
      .define_singleton_function("new_edge_shape", &new_edge_shape, Rice::Arg("body"),
                                 Rice::Arg("coordinates"), owned)
      .define_singleton_function("new_polygon_shape", &new_polygon_shape, Rice::Arg("body"),
                                 Rice::Arg("coordinates"), owned)
      .define_singleton_function("new_chain_shape", &new_chain_shape, Rice::Arg("body"),
                                 Rice::Arg("loop"), Rice::Arg("coordinates"), owned)
      .define_singleton_function("new_revolute_joint", &new_revolute_joint, Rice::Arg("body1"),
                                 Rice::Arg("body2"), Rice::Arg("anchors"),
                                 Rice::Arg("collide_connected"),
                                 Rice::Arg("reference_angle") = std::optional<double>(), owned)
      .define_singleton_function("new_friction_joint", &new_friction_joint, Rice::Arg("body1"),
                                 Rice::Arg("body2"), Rice::Arg("anchors"),
                                 Rice::Arg("collide_connected"), owned)
      .define_singleton_function("new_weld_joint", &new_weld_joint, Rice::Arg("body1"),
                                 Rice::Arg("body2"), Rice::Arg("anchors"),
                                 Rice::Arg("collide_connected"),
                                 Rice::Arg("reference_angle") = std::optional<double>(), owned)
      .define_singleton_function("new_prismatic_joint", &new_prismatic_joint, Rice::Arg("body1"),
                                 Rice::Arg("body2"), Rice::Arg("anchors"),
                                 Rice::Arg("collide_connected"),
                                 Rice::Arg("reference_angle") = std::optional<double>(), owned)
      .define_singleton_function("new_wheel_joint", &new_wheel_joint, Rice::Arg("body1"),
                                 Rice::Arg("body2"), Rice::Arg("anchors"),
                                 Rice::Arg("collide_connected"), owned)
      .define_singleton_function("distance", &distance, Rice::Arg("shape_a"), Rice::Arg("shape_b"));
}

} // namespace lota::native
