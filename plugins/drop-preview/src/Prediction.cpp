#define WLR_USE_UNSTABLE

#include "Prediction.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/shared/complex/ComplexDataTypes.hpp>
#include <hyprland/src/config/shared/workspace/WorkspaceRuleManager.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/view/Group.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowGroupMembership.hpp>
#include <hyprland/src/helpers/MiscFunctions.hpp>
#include <hyprland/src/helpers/math/Direction.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/TiledAlgorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/state/MonitorLayoutController.hpp>

#include <algorithm>
#include <cmath>

using namespace Layout;
using namespace Layout::Tiled;

template <typename TAG, typename TAG::type MEMBER>
struct SPrivateAccess {
    friend typename TAG::type privateMember(TAG) {
        return MEMBER;
    }
};

struct SDwindleNodesTag {
    using type = std::vector<SP<SDwindleNodeData>> CDwindleAlgorithm::*;
    friend type privateMember(SDwindleNodesTag);
};
template struct SPrivateAccess<SDwindleNodesTag, &CDwindleAlgorithm::m_dwindleNodesData>;

struct SDwindleOverrideDirTag {
    using type = Math::eDirection CDwindleAlgorithm::*;
    friend type privateMember(SDwindleOverrideDirTag);
};
template struct SPrivateAccess<SDwindleOverrideDirTag, &CDwindleAlgorithm::m_overrideDirection>;

static bool sticks(double a, double b) {
    return std::abs(a - b) < 2;
}

static CBox windowGoalBox(PHLWINDOW w) {
    return w->geometricBox(Desktop::View::IGeometric::GEOMETRIC_GOAL);
}

static CBox nodeBoxToWindowBox(const CBox& node, SP<CSpace> space, PHLWINDOW dragged) {
    static auto PGAPSINDATA = CConfigValue<Config::IComplexConfigValue>("general:gaps_in");
    const auto* PGAPSIN     = sc<Config::CCssGapData*>(PGAPSINDATA.ptr());
    const auto  RULE        = Config::workspaceRuleMgr()->getWorkspaceRuleFor(space->workspace());
    const auto  GAPSIN      = RULE && RULE->m_gapsIn.has_value() ? RULE->m_gapsIn.value() : *PGAPSIN;
    const auto  WORKAREA    = space->workArea();

    CBox        nodeBox = node;
    nodeBox.round();

    const bool LEFT   = sticks(node.x, WORKAREA.x);
    const bool RIGHT  = sticks(node.x + node.w, WORKAREA.x + WORKAREA.w);
    const bool TOP    = sticks(node.y, WORKAREA.y);
    const bool BOTTOM = sticks(node.y + node.h, WORKAREA.y + WORKAREA.h);

    const Vector2D TL = {LEFT ? 0.0 : sc<double>(GAPSIN.m_left), TOP ? 0.0 : sc<double>(GAPSIN.m_top)};
    const Vector2D BR = {RIGHT ? 0.0 : sc<double>(GAPSIN.m_right), BOTTOM ? 0.0 : sc<double>(GAPSIN.m_bottom)};

    Vector2D       pos  = nodeBox.pos() + TL;
    Vector2D       size = nodeBox.size() - TL - BR;

    const auto     RESERVED = dragged->getFullWindowReservedArea();
    pos                     = pos + RESERVED.topLeft;
    size                    = size - (RESERVED.topLeft + RESERVED.bottomRight);

    return CBox{pos, size}.noNegativeSize();
}

static SP<SDwindleNodeData> closestNode(const std::vector<SP<SDwindleNodeData>>& nodes, const Vector2D& point, SP<ITarget> skip) {
    SP<SDwindleNodeData> res;
    double               distClosest = -1;
    for (const auto& n : nodes) {
        if (skip && n->pTarget == skip)
            continue;

        if (!n->pTarget || !Desktop::View::validMapped(n->pTarget->window()))
            continue;

        const double DIST = vecToRectDistanceSquared(point, n->box.pos(), n->box.pos() + n->box.size());
        if (!res || DIST < distClosest) {
            res         = n;
            distClosest = DIST;
        }
    }
    return res;
}

static std::optional<CBox> predictDwindle(CDwindleAlgorithm* dwindle, SP<ITarget> target, SP<CSpace> space, PHLWINDOW dragged, const Vector2D& mouse) {
    const auto& NODES      = dwindle->*privateMember(SDwindleNodesTag{});
    const auto  OVERRIDE   = dwindle->*privateMember(SDwindleOverrideDirTag{});
    const auto  PWORKSPACE = space->workspace();
    const auto  PMONITOR   = PWORKSPACE->m_monitor.lock();
    const auto  ACTIVE_MON = Desktop::focusState()->monitor();

    if (!PMONITOR || !ACTIVE_MON) {
        return std::nullopt;
    }

    static auto          PUSEACTIVE = CConfigValue<Config::INTEGER>("dwindle:use_active_for_splits");

    SP<SDwindleNodeData> openingOn;

    if ((PWORKSPACE == ACTIVE_MON->m_activeWorkspace || (PWORKSPACE->type() == Workspace::eWorkspaceType::SPECIAL && PMONITOR->m_activeSpecialWorkspace)) && !*PUSEACTIVE) {
        const auto HIT = Desktop::viewState()->hitTest().windowAt(mouse, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::SKIP_FULLSCREEN_PRIORITY,
                                                                    dragged);
        openingOn      = dwindle->getNodeFromWindow(HIT);

        if (!openingOn && !dragged->layoutBox().containsPoint(mouse) && State::monitorLayoutController()->isPointOnReservedArea(mouse, ACTIVE_MON))
            openingOn = closestNode(NODES, mouse, nullptr);
    } else if (*PUSEACTIVE) {
        openingOn = closestNode(NODES, mouse, target);
    } else
        openingOn = NODES.empty() ? nullptr : NODES.front();

    const auto PREDSIZEMAX = openingOn ? openingOn->box.size() : PMONITOR->m_size;
    if (const auto MAXSIZE = target->maxSize().value_or(Math::VECTOR2D_MAX); MAXSIZE.x < PREDSIZEMAX.x || MAXSIZE.y < PREDSIZEMAX.y)
        return std::nullopt;

    if (!openingOn || openingOn->pTarget.lock() == target) {
        openingOn.reset();
        for (const auto& n : NODES) {
            const auto LOCKED = n->pTarget.lock();
            if (!LOCKED || LOCKED == target)
                continue;
            openingOn = n;
            break;
        }
    }

    if (!openingOn)
        return nodeBoxToWindowBox(space->workArea(), space, dragged);

    static auto PDEFAULTSPLIT     = CConfigValue<Config::FLOAT>("dwindle:default_split_ratio");
    static auto PWIDTHMULTIPLIER  = CConfigValue<Config::FLOAT>("dwindle:split_width_multiplier");
    static auto PSMARTSPLIT       = CConfigValue<Config::INTEGER>("dwindle:smart_split");
    static auto PSPLITBIAS        = CConfigValue<Config::INTEGER>("dwindle:split_bias");
    static auto PPRECISEMOUSEMOVE = CConfigValue<Config::INTEGER>("dwindle:precise_mouse_move");
    static auto PPRESERVESPLIT    = CConfigValue<Config::INTEGER>("dwindle:preserve_split");

    const CBox  PARENT     = openingOn->box;
    float       splitRatio = std::clamp(*PDEFAULTSPLIT, 0.1F, 1.9F);
    const bool  SIDEBYSIDE = PARENT.w > PARENT.h * *PWIDTHMULTIPLIER;
    bool        splitTop   = !SIDEBYSIDE;
    bool        newIsFirst = false;
    bool        horizontalOverride = false, verticalOverride = false;

    if (OVERRIDE != Math::DIRECTION_DEFAULT) {
        if (OVERRIDE % 2 == 0)
            verticalOverride = true;
        else
            horizontalOverride = true;

        newIsFirst = OVERRIDE % 3 == 0;
    } else if (*PSMARTSPLIT == 1 || *PPRECISEMOUSEMOVE == 1) {
        const auto PARENT_CENTER      = PARENT.pos() + PARENT.size() / 2;
        const auto PARENT_PROPORTIONS = PARENT.h / PARENT.w;
        const auto DELTA              = mouse - PARENT_CENTER;
        const auto DELTA_SLOPE        = DELTA.y / DELTA.x;

        if (std::abs(DELTA_SLOPE) < PARENT_PROPORTIONS) {
            splitTop   = false;
            newIsFirst = DELTA.x <= 0;
        } else {
            splitTop   = true;
            newIsFirst = DELTA.y <= 0;
        }
    } else
        newIsFirst = (SIDEBYSIDE && mouse.x < PARENT.x + (PARENT.w / 2.F)) || (!SIDEBYSIDE && mouse.y < PARENT.y + (PARENT.h / 2.F));

    if (*PSPLITBIAS && newIsFirst)
        splitRatio = 2.F - splitRatio;

    if (*PPRESERVESPLIT == 0 && *PSMARTSPLIT == 0 && *PPRECISEMOUSEMOVE == 0)
        splitTop = PARENT.h * *PWIDTHMULTIPLIER > PARENT.w;

    if (verticalOverride)
        splitTop = true;
    else if (horizontalOverride)
        splitTop = false;

    CBox child0, child1;
    if (!splitTop) {
        const float FIRSTSIZE = PARENT.w / 2.0 * splitRatio;
        child0                = CBox{PARENT.x, PARENT.y, FIRSTSIZE, PARENT.h}.noNegativeSize();
        child1                = CBox{PARENT.x + FIRSTSIZE, PARENT.y, PARENT.w - FIRSTSIZE, PARENT.h}.noNegativeSize();
    } else {
        const float FIRSTSIZE = PARENT.h / 2.0 * splitRatio;
        child0                = CBox{PARENT.x, PARENT.y, PARENT.w, FIRSTSIZE}.noNegativeSize();
        child1                = CBox{PARENT.x, PARENT.y + FIRSTSIZE, PARENT.w, PARENT.h - FIRSTSIZE}.noNegativeSize();
    }

    return nodeBoxToWindowBox(newIsFirst ? child0 : child1, space, dragged);
}

static std::optional<CBox> predictGeneric(SP<CSpace> space, PHLWINDOW dragged, const Vector2D& mouse) {
    const auto HIT =
        Desktop::viewState()->hitTest().windowAt(mouse, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::SKIP_FULLSCREEN_PRIORITY, dragged);

    if (HIT && !HIT->isFloating() && HIT->m_workspace == space->workspace())
        return windowGoalBox(HIT);

    if (space->algorithm()->tiledTargets() == 0)
        return nodeBoxToWindowBox(space->workArea(), space, dragged);

    return std::nullopt;
}

std::optional<SDropPrediction> predictDrop(bool genericFallback) {
    if (!g_layoutManager)
        return std::nullopt;

    const auto& DRAG   = g_layoutManager->dragController();
    const auto  TARGET = DRAG->target();

    if (!TARGET || DRAG->mode() != MBIND_MOVE || !DRAG->draggingTiled() || !TARGET->floating())
        return std::nullopt;

    const auto DRAGGED = TARGET->window();
    if (!Desktop::View::validMapped(DRAGGED))
        return std::nullopt;

    const auto SPACE = TARGET->space();
    if (!SPACE || !SPACE->workspace() || !SPACE->algorithm())
        return std::nullopt;

    const auto MOUSE = g_pInputManager->getMouseCoordsInternal();

    static auto PDRAGINTOGROUP = CConfigValue<Config::INTEGER>("group:drag_into_group");
    if (*PDRAGINTOGROUP == 1) {
        const auto UNDER =
            Desktop::viewState()->hitTest().windowAt(MOUSE, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING, DRAGGED);
        if (UNDER) {
            const auto& UNDERGROUP = UNDER->grouping().group();
            if (UNDERGROUP && DRAGGED->grouping().canBeGroupedInto(UNDERGROUP))
                return SDropPrediction{.box = windowGoalBox(UNDER), .dragged = DRAGGED};
        }
    }

    std::optional<CBox> box;
    if (auto* dwindle = dynamic_cast<CDwindleAlgorithm*>(SPACE->algorithm()->tiledAlgo().get()); dwindle)
        box = predictDwindle(dwindle, TARGET, SPACE, DRAGGED, MOUSE);
    else if (genericFallback)
        box = predictGeneric(SPACE, DRAGGED, MOUSE);

    if (!box || box->w < 1 || box->h < 1)
        return std::nullopt;

    return SDropPrediction{.box = *box, .dragged = DRAGGED};
}
