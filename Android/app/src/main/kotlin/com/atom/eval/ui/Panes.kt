package com.atom.eval.ui

import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.layout.PaneScaffoldDirective
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.runtime.Composable

/**
 * The panes Material lays out for this window, at most [maxPanes] side by side.
 * Focus does not move into the pane shown: it would land on the search field of
 * the list and open the keyboard each time the list appears.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun paneScaffoldDirective(maxPanes: Int = Int.MAX_VALUE): PaneScaffoldDirective {
    val directive = calculatePaneScaffoldDirective(currentWindowAdaptiveInfoV2())
    return PaneScaffoldDirective(
        maxHorizontalPartitions = minOf(maxPanes, directive.maxHorizontalPartitions),
        horizontalPartitionSpacerSize = directive.horizontalPartitionSpacerSize,
        maxVerticalPartitions = directive.maxVerticalPartitions,
        verticalPartitionSpacerSize = directive.verticalPartitionSpacerSize,
        defaultPanePreferredWidth = directive.defaultPanePreferredWidth,
        defaultPanePreferredHeight = directive.defaultPanePreferredHeight,
        excludedBounds = directive.excludedBounds,
        shouldAutoFocusCurrentDestination = false,
    )
}
