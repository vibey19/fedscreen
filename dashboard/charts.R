# The charts.
#
# These live in dashboard/ rather than in R/ on purpose. Everything in R/ is
# pipeline code that runs at a site or at the centre, and none of it should
# need a plotting library installed. This file is presentation only, so the
# pipeline never loads it.
#
# Every chart is built the same way: a ggplot, then plotly::ggplotly() to make
# it interactive. One idiom, repeated three times, so there is only one thing
# to understand.

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
})

# ---- Shared look ----------------------------------------------------------

#' A calm theme: light grid, no boxes, nothing competing with the data
theme_fedscreen <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = "#e9e9e9"),
      strip.text = element_text(face = "bold", size = base_size * 0.8,
                               hjust = 0),
      axis.title = element_text(size = base_size * 0.8, colour = "#555555"),
      legend.position = "top",
      legend.title = element_blank()
    )
}

#' Hand a ggplot to plotly, showing only the tooltip we wrote ourselves
#'
#' plotly builds a tooltip out of every mapped variable by default, which ends
#' up showing the internal column names. `tooltip = "text"` tells it to use
#' only the `text` aesthetic, which is the sentence from add_tooltip() below.
as_interactive <- function(p, height = NULL) {
  plotly::ggplotly(p, tooltip = "text", height = height) %>%
    plotly::config(displayModeBar = FALSE) %>%
    plotly::layout(
      legend = list(orientation = "h", x = 0, y = 1.12, title = list(text = "")),
      margin = list(t = 40, b = 60)
    )
}

#' The sentence shown when you hover over a point
#'
#' Written out as a column rather than left to plotly, so a reader of the chart
#' sees the same formatting (percent or per 1,000) as a reader of the table.
add_tooltip <- function(level) {
  level %>%
    mutate(
      estimate_text = format_estimate(.data$estimate, .data$measure,
                                      .data$suppressed),
      interval_text = format_interval(.data$ci_lower, .data$ci_upper,
                                      .data$measure, .data$suppressed),
      text = paste0(
        "<b>", .data$site, "</b><br>",
        .data$indicator_label, "<br>",
        .data$estimate_text, " (95% CI ", .data$interval_text, ")<br>",
        format_count(.data$numerator, .data$denominator, .data$suppressed),
        " people"
      )
    )
}

# Both measures on one chart would put a percentage next to a rate per 1,000,
# so the pages split them. These are the labels for the two halves.
MEASURE_LABELS <- c(proportion = "Measured as a percentage",
                    rate_per_1000 = "Measured per 1,000 people")

#' Keep only the indicators measured one way
#'
#' Every chart holds one measure. A percentage and a rate per 1,000 cannot
#' share an axis, and splitting them here means a panel heading does not have
#' to carry its own unit.
one_measure_level <- function(level, measure_name) {
  rows <- level %>% filter(.data$measure == measure_name)

  if (nrow(rows) == 0) {
    stop("no rows measured as ", measure_name, call. = FALSE)
  }
  rows
}

#' The same, formatted and ready for the comparison chart
one_measure <- function(level, measure_name) {
  one_measure_level(level, measure_name) %>%
    to_display_scale() %>%
    add_tooltip()
}

#' Everything a grid of panels needs: display scale, tooltip, panel heading
#'
#' `plottable()` drops the suppressed rows last, after the tooltip is built, so
#' nothing half formatted survives into a chart.
panel_rows <- function(level) {
  rows <- level %>%
    to_display_scale() %>%
    add_tooltip() %>%
    plottable() %>%
    mutate(
      panel = as.character(.data$indicator_short),
      # NA for the "All" rows, which the trend chart never draws anyway.
      year = suppressWarnings(as.integer(.data$screening_year))
    )

  # Panel headings in pathway order. indicator_label is already a factor in
  # that order, so sorting the distinct pairs by it gives the level order.
  headings <- rows %>%
    distinct(.data$indicator_short, .data$panel) %>%
    arrange(.data$indicator_short)

  rows %>% mutate(panel = factor(.data$panel, levels = headings$panel))
}

# ---- The charts -----------------------------------------------------------

#' Sites side by side, one row per indicator
#'
#' A dot for the estimate and a line for the 95% interval. Horizontal, because
#' indicator names are long and this reads on a phone.
comparison_chart <- function(level, measure_name, height = 400) {
  rows <- plottable(one_measure(level, measure_name))

  p <- ggplot(rows, aes(x = .data$value, y = .data$indicator_short,
                        colour = .data$site, text = .data$text)) +
    geom_linerange(aes(xmin = .data$value_lower, xmax = .data$value_upper),
                   position = position_dodge(width = 0.6), linewidth = 0.6,
                   show.legend = FALSE) +
    geom_point(position = position_dodge(width = 0.6), size = 2.2) +
    scale_colour_manual(values = SITE_COLOURS) +
    # limits = rev puts the first indicator at the top, so the chart reads
    # down the pathway the way the table does.
    scale_y_discrete(limits = rev) +
    labs(x = NULL, y = NULL) +
    theme_fedscreen()

  as_interactive(p, height = height)
}

# One panel per indicator, stacked. Two columns would be quicker to scan on a
# laptop, but at phone width the panel headings run into each other, and a
# chart you cannot read is worse than a long one you can scroll.
PANEL_HEIGHT <- 135
GRID_PADDING <- 95

#' Tall enough for the panels it holds
grid_height <- function(rows) {
  GRID_PADDING + PANEL_HEIGHT * length(unique(rows$panel))
}

#' Indicators of one measure over the three screening years, one line per site
trend_grid <- function(level, measure_name) {
  rows <- panel_rows(one_measure_level(level, measure_name))

  # The group goes on the line only. Putting it in the top level aes() would
  # also group the error bars, which they do not need.
  p <- ggplot(rows, aes(x = .data$year, y = .data$value, colour = .data$site,
                        text = .data$text)) +
    geom_errorbar(aes(ymin = .data$value_lower, ymax = .data$value_upper),
                  width = 0.12, linewidth = 0.5, alpha = 0.6,
                  show.legend = FALSE) +
    geom_line(aes(group = .data$site), linewidth = 0.7) +
    geom_point(size = 1.9) +
    scale_colour_manual(values = SITE_COLOURS) +
    scale_x_continuous(breaks = sort(unique(rows$year))) +
    facet_wrap(~ panel, ncol = 1, scales = "free_y") +
    labs(x = NULL, y = NULL) +
    theme_fedscreen()

  as_interactive(p, height = grid_height(rows))
}

#' Indicators of one measure split one way, by sex or by age group
#'
#' `level` comes from group_level(), which has already picked the rows split
#' the one way and put the groups in a column called `group`.
breakdown_grid <- function(level, measure_name) {
  rows <- panel_rows(one_measure_level(level, measure_name))

  p <- ggplot(rows, aes(x = .data$group, y = .data$value, colour = .data$site,
                        text = .data$text)) +
    geom_errorbar(aes(ymin = .data$value_lower, ymax = .data$value_upper),
                  position = position_dodge(width = 0.55), width = 0.25,
                  linewidth = 0.5, alpha = 0.6, show.legend = FALSE) +
    geom_point(position = position_dodge(width = 0.55), size = 1.9) +
    scale_colour_manual(values = SITE_COLOURS) +
    facet_wrap(~ panel, ncol = 1, scales = "free_y") +
    labs(x = NULL, y = NULL) +
    theme_fedscreen()

  as_interactive(p, height = grid_height(rows))
}
