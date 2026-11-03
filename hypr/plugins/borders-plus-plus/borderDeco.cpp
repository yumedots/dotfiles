#include "borderDeco.hpp"

#include <algorithm>

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/BorderPassElement.hpp>
#include <hyprutils/memory/Casts.hpp>
using namespace Hyprutils::Memory;
#include "globals.hpp"

static size_t borderCount() {
    return std::clamp<Config::INTEGER>(vars.addBorders->value(), 0, static_cast<Config::INTEGER>(vars.borderSizes.size()));
}

CBordersPlusPlus::CBordersPlusPlus(PHLWINDOW pWindow) : IHyprWindowDecoration(pWindow), m_pWindow(pWindow) {
    m_lastWindowPos  = pWindow->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    m_lastWindowSize = pWindow->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
}

CBordersPlusPlus::~CBordersPlusPlus() {
    damageEntire();
}

SDecorationPositioningInfo CBordersPlusPlus::getPositioningInfo() {
    SDecorationPositioningInfo info;
    info.policy   = DECORATION_POSITION_STICKY;
    info.reserved = true;
    info.priority = 9990;
    info.edges    = DECORATION_EDGE_BOTTOM | DECORATION_EDGE_LEFT | DECORATION_EDGE_RIGHT | DECORATION_EDGE_TOP;

    if (m_fLastThickness == 0) {
        double size = 0;

        for (size_t i = 0; i < borderCount(); ++i) {
            size += vars.borderSizes[i]->value();
        }

        info.desiredExtents = {{size, size}, {size, size}};
        m_fLastThickness    = size;
    } else
        info.desiredExtents = {{m_fLastThickness, m_fLastThickness}, {m_fLastThickness, m_fLastThickness}};

    return info;
}

void CBordersPlusPlus::onPositioningReply(const SDecorationPositioningReply& reply) {
    m_bAssignedGeometry = reply.assignedGeometry;
}

uint64_t CBordersPlusPlus::getDecorationFlags() {
    return DECORATION_PART_OF_MAIN_WINDOW;
}

eDecorationLayer CBordersPlusPlus::getDecorationLayer() {
    return DECORATION_LAYER_OVER;
}

std::string CBordersPlusPlus::getDisplayName() {
    return "Borders++";
}

void CBordersPlusPlus::draw(Render::CRenderContext& ctx, PHLMONITOR pMonitor, const float& a, const Render::SWindowRenderPresentation& presentation) {
    if (!validMapped(m_pWindow))
        return;

    const auto PWINDOW = m_pWindow.lock();

    if (!PWINDOW->m_ruleApplicator->decorate().valueOrDefault())
        return;

    const auto BORDERS = borderCount();

    if (BORDERS < 1)
        return;

    if (m_bAssignedGeometry.width < m_seExtents.topLeft.x + 1 || m_bAssignedGeometry.height < m_seExtents.topLeft.y + 1)
        return;

    static auto PBORDERSIZE = CConfigValue<Config::INTEGER>("general:border_size");

    const auto  NATURALROUND  = vars.naturalRounding->value();
    auto        rounding      = PWINDOW->presentation().rounding() == 0 ? 0 : (PWINDOW->presentation().rounding() + *PBORDERSIZE) * pMonitor->m_scale;
    const auto  ROUNDINGPOWER = PWINDOW->presentation().roundingPower();
    const auto  ORIGINALROUND = rounding;

    CBox        fullBox = PWINDOW->getWindowMainSurfaceBox();
    fullBox.translate(presentation.floatingOffset - pMonitor->m_position + presentation.workspaceOffset);
    fullBox.scale(pMonitor->m_scale).round();

    if (fullBox.width < 1 || fullBox.height < 1)
        return;

    double fullThickness = 0;

    for (size_t i = 0; i < BORDERS; ++i) {
        const int THISBORDERSIZE = vars.borderSizes[i]->value() == -1 ? *PBORDERSIZE : vars.borderSizes[i]->value();
        fullThickness += THISBORDERSIZE;
    }

    fullBox.expand(std::round(PWINDOW->presentation().borderSize() * pMonitor->m_scale));

    int prevScaled = 0;

    for (size_t i = 0; i < BORDERS; ++i) {
        const int THISBORDERSIZE = vars.borderSizes[i]->value() == -1 ? *PBORDERSIZE : vars.borderSizes[i]->value();

        if (i != 0) {
            rounding += rounding == 0 ? 0 : prevScaled;
            fullBox.expand(prevScaled);
        }

        if (fullBox.width < 1 || fullBox.height < 1)
            break;

        CBorderPassElement::SBorderData data;
        data.box           = fullBox;
        data.grad1         = Config::CGradientValueData(CHyprColor{static_cast<uint64_t>(vars.borderColors[i]->value())});
        data.round         = NATURALROUND ? sc<int>(ORIGINALROUND) : sc<int>(rounding);
        data.roundingPower = ROUNDINGPOWER;
        data.borderSize    = THISBORDERSIZE;
        data.a             = a;
        data.outerRound    = NATURALROUND ? sc<int>(ORIGINALROUND) : -1;

        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CBorderPassElement>(data));

        prevScaled = std::round(THISBORDERSIZE * pMonitor->m_scale);
    }

    m_seExtents = {{fullThickness, fullThickness}, {fullThickness, fullThickness}};

    m_bLastRelativeBox = CBox{0, 0, m_lastWindowSize.x, m_lastWindowSize.y}.addExtents(m_seExtents);

    if (fullThickness != m_fLastThickness) {
        m_fLastThickness = fullThickness;
        g_pDecorationPositioner->repositionDeco(this);
    }
}

eDecorationType CBordersPlusPlus::getDecorationType() {
    return DECORATION_CUSTOM;
}

void CBordersPlusPlus::updateWindow(PHLWINDOW pWindow) {
    m_lastWindowPos  = pWindow->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    m_lastWindowSize = pWindow->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);

    damageEntire();
}

void CBordersPlusPlus::damageEntire() {
    CBox dm = m_bLastRelativeBox.copy().translate(m_lastWindowPos).expand(2);
    g_pHyprRenderer->damageBox(dm);
}
