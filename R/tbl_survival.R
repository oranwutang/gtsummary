#' Creates table of univariate summary statistics for time-to-event endpoints
#'
#' \lifecycle{deprecated}
#' Please use [tbl_survfit].
#' Function takes a `survfit` object as an argument, and provides a
#' formatted summary of the results
#'
#' @keywords internal
#' @name tbl_survival
#'
#' @param x A survfit object with a no stratification
#' (e.g. `survfit(Surv(ttdeath, death) ~ 1, trial)`), or a single stratifying
#' variable (e.g. `survfit(Surv(ttdeath, death) ~ trt, trial)`)
#' @param times Numeric vector of times for which to return survival probabilities.
#' @param probs Numeric vector of probabilities with values in (0,1)
#' specifying the survival quantiles to return
#' @param label String defining the label shown for the time or prob column.
#' Default is `"{time}"` or `"{prob*100}%"`.  The input uses [glue::glue] notation to
#' convert the string into a label.  A common label may be `"{time} Months"`, which
#' would resolve to "6 Months" or "12 Months" depending on specified \code{times}.
#' @param level_label Used when survival results are stratified.
#' It is a string defining the label shown.  The input uses
#' [glue::glue] notation to convert the string into a label.
#' The default is \code{"{level}, N = {n}"}.  Other information available to
#' call are `'{n}'`, `'{level}'`, `'{n.event.tot}'`, `'{n.event.strata}'`, and
#' `'{strata}'`. See below for details.
#' @param header_label String to be displayed as column header.
#' Default is \code{'**Time**'} when `time` is specified, and
#' \code{'**Quantile**'} when `probs` is specified.
#' @param header_estimate String to be displayed as column header of the Kaplan-Meier
#' estimate.  Default is \code{'**Probability**'} when `time` is specified, and
#' \code{'**Time**'} when `probs` is specified.
#' @param failure Calculate failure probabilities rather than survival probabilities.
#' Default is `FALSE`.  Does NOT apply to survival quantile requests
#' @param missing String indicating what to replace missing confidence
#' limits with in output.  Default is `missing = "-"`
#' @param estimate_fun Function used to format the estimate and confidence
#' limits. The default is `style_percent(x, symbol = TRUE)` for survival
#' probabilities, and
#' `style_sigfig(x, digits = 3)` for time estimates.
#' @param ... Not used
NULL

#' @rdname tbl_survival
#' @export
tbl_survival <- function(x, ...) {
  lifecycle::deprecate_warn(
    when = "1.4.0",
    what = "gtsummary::tbl_survival()",
    with = "tbl_survfit()"
  )
  UseMethod("tbl_survival")
}


#' @rdname tbl_survival
#' @export
tbl_survival.survfit <- function(x, times = NULL, probs = NULL,
                                 label = ifelse(is.null(probs), "{time}", "{prob*100}%"),
                                 level_label = "{level}, N = {n}",
                                 header_label = NULL,
                                 header_estimate = NULL,
                                 failure = FALSE,
                                 missing = "-",
                                 estimate_fun = NULL,
                                 ...) {

  # setting defaults -----------------------------------------------------------
  estimate_fun <-
    estimate_fun %||%
    getOption("gtsummary.tbl_survival.estimate_fun") %||%
    switch(is.null(times) + 1,
      partial(style_percent, symbol = TRUE),
      partial(style_sigfig, digits = 3)
    )

  # input checks ---------------------------------------------------------------
  assert_package("survival", "tbl_survival()")

  if (c(is.null(times), is.null(probs)) %>% sum() != 1) {
    stop("One and only one of 'times' and 'probs' must be specified.")
  }
  if (!rlang::is_string(label) || !rlang::is_string(level_label) ||
    !rlang::is_string(header_label %||% "") ||
    !rlang::is_string(header_label %||% "")) {
    stop("'label', 'header_label', and 'level_label' arguments must be string of length one.")
  }

  # defining default headers ---------------------------------------------------
  header_label <-
    header_label %||% ifelse(is.null(probs), "**Time**", "**Quantile**")
  header_estimate <-
    header_estimate %||% ifelse(is.null(probs), "**Probability**", "**Time**")

  # defining estimate_fun ------------------------------------------------------
  # assigning a function to formating estimates and conf.high and conf.low
  estimate_fun <-
    estimate_fun %||%
    switch(is.null(times) + 1,
      partial(style_percent, symbol = TRUE),
      partial(style_sigfig, digits = 3)
    )

  # putting results into tibble -------------------------------------------------
  if (!is.null(probs)) {
    table_long <- surv_quantile(x, probs)
  } else if (!is.null(times)) table_long <- surv_time(x, times, failure)

  # adding additional information to the results table -------------------------
  # if the results are stratified
  if (!is.null(x$strata)) {
    table_long <-
      table_long %>%
      left_join(
        tibble(
          strata = x$strata %>% names(),
          n = x$n,
          n.event.tot = x$n.event %>% sum()
        ),
        by = "strata"
      ) %>%
      # merging in number of events within stratum
      left_join(
        summary(x) %>%
          {
            tibble::tibble(
              strata = .[["strata"]] %>% as.character(),
              n.event.strata = .[["n.event"]]
            )
          } %>%
          dplyr::group_by(.data$strata) %>%
          dplyr::summarise(
            n.event.strata = sum(.data$n.event.strata)
          ),
        by = "strata"
      ) %>%
      # parsing the stratum, and creating
      mutate(
        variable = str_split(.data$strata, pattern = "=", n = 2) %>% map_chr(pluck(1)),
        level = str_split(.data$strata, pattern = "=", n = 2) %>% map_chr(pluck(2)),
        level_label = glue(level_label)
      )
  }
  # if the results are NOT stratified
  else {
    table_long <-
      table_long %>%
      mutate(
        n = x$n,
        n.event.tot = x %>%
          summary(times = max(x$time)) %>%
          pluck("n.event")
      )
  }

  # IF NOT WIDE OPTIONS SPECIFIED, APPLY LABELS AND GT CALLS -------------------
  # creating label column
  table_long <-
    table_long %>%
    mutate(
      label = glue(label),
      ci = case_when(
        !is.na(.data$conf.low) & !is.na(.data$conf.high) ~
        glue("{estimate_fun(conf.low)}, {estimate_fun(conf.high)}"),
        is.na(.data$conf.low) & !is.na(.data$conf.high) ~
        glue("{missing}, {estimate_fun(conf.high)}"),
        !is.na(.data$conf.low) & is.na(.data$conf.high) ~
        glue("{estimate_fun(conf.low)}, {missing}"),
        is.na(.data$conf.low) & is.na(.data$conf.high) ~
        NA_character_
      )
    ) %>%
    select(starts_with("level_label"), c("label", "estimate", "conf.low", "conf.high", "ci"), everything())
  table_body <- table_long %>% mutate(row_type = "label")

  # table of column headers
  table_header <-
    tibble(column = names(table_body)) %>%
    table_header_fill_missing() %>%
    table_header_fmt_fun(estimate = estimate_fun) %>%
    mutate(
      footnote_abbrev = case_when(
        .data$column == "ci" ~ "CI = Confidence Interval",
        TRUE ~ .data$footnote_abbrev
      )
    )

  # creating object to return
  level_label <- intersect("level_label", names(table_body)) %>%
    list() %>%
    compact()
  result <- list()
  result[["table_body"]] <- table_body %>% group_by(!!!syms(level_label))
  result[["table_header"]] <- table_header
  result[["table_long"]] <- table_long
  result[["survfit"]] <- x
  result[["call_list"]] <- list(tbl_survival = match.call())

  # specifying labels
  result$table_header <-
    result$table_header %>%
    dplyr::rows_update(
      tibble::tribble(
        ~column, ~label,
        "label", glue("{header_label}") %>% as.character(),
        "estimate", glue("{header_estimate}") %>% as.character(),
        "ci", glue("**{x$conf.int*100}% CI**") %>% as.character()
      ) %>%
        mutate(hide = FALSE),
      by = "column"
    )


  # renaming grouping variable, 'level_label', added in v1.4.0--could cause breaking changes
  if ("level_label" %in% names(result$table_body)) {
    result$table_header <-
      result$table_header %>%
      mutate(
        column = ifelse(.data$column == "level_label", "groupname_col", .data$column),
        label = ifelse(.data$column == "groupname_col", "**Group**", .data$label),
        align = ifelse(.data$column == "groupname_col", "left", .data$align),
        hide = ifelse(.data$column == "groupname_col", FALSE, .data$hide),
      )
    result$table_body <-
      rename(result$table_body, groupname_col = .data$level_label) %>%
      ungroup()
  }

  # returning results
  class(result) <- c("tbl_survival", "gtsummary")
  result
}




surv_time <- function(x, times, failure) {
  # getting survival estimates
  survfit_summary <- x %>%
    summary(times = times)

  # converting output into tibble
  table_body <-
    survfit_summary %>%
    {
      .[names(.) %in% c(
        "strata", "time", "surv",
        "lower", "upper", "n.risk", "n.event"
      )]
    } %>%
    as_tibble() %>%
    rename(
      estimate = .data$surv,
      conf.low = .data$lower,
      conf.high = .data$upper
    )

  # converting strata to character
  if ("strata" %in% names(table_body)) {
    table_body <-
      table_body %>%
      mutate(strata = as.character(.data$strata))
  }

  # converting probabilites to failure if requested
  if (failure == TRUE) {
    table_body <-
      table_body %>%
      mutate_at(vars(.data$estimate, .data$conf.low, .data$conf.high), ~ 1 - .) %>%
      rename(
        conf.low = .data$conf.high,
        conf.high = .data$conf.low
      )
  }

  table_body
}

surv_quantile <- function(x, probs) {
  # logical indicating whether estimates are stratified
  stratified <- !is.null(x$strata)

  # parsing results for stratified models
  if (stratified == TRUE) {
    # getting survival quantile estimates into tibble
    survfit_quantile <- x %>%
      stats::quantile(probs = probs) %>%
      purrr::imap(
        ~ t(.x) %>%
          {
            dplyr::bind_cols(
              tibble::tibble(prob = row.names(.)),
              tibble::as_tibble(.)
            )
          } %>%
          tidyr::gather("strata", !!.y, -prob)
      )

    # merging all result tibbles together
    table_body <-
      survfit_quantile[[1]] %>%
      dplyr::left_join(survfit_quantile[[2]], by = c("prob", "strata")) %>%
      dplyr::left_join(survfit_quantile[[3]], by = c("prob", "strata")) %>%
      rename(estimate = .data$quantile)
  }

  else {
    survfit_quantile <-
      x %>%
      stats::quantile(probs = probs) %>%
      purrr::imap(
        ~ tibble::tibble(
          prob = names(.x),
          !!.y := .x
        )
      )

    # merging all result tibbles together
    table_body <-
      survfit_quantile[[1]] %>%
      dplyr::left_join(survfit_quantile[[2]], by = "prob") %>%
      dplyr::left_join(survfit_quantile[[3]], by = "prob") %>%
      rename(estimate = .data$quantile)
  }

  table_body %>%
    mutate(prob = as.numeric(.data$prob) / 100) %>%
    rename(
      conf.low = .data$lower,
      conf.high = .data$upper
    )
}


# table_header_fmt_fun ---------------------------------------------------------
# this function makes it easy to update table_header with new formatting functions
# e.g. table_header_fmt_fun(table_header, p.value = pvalue_fun)
#' Function makes it easy to update table_header with new formatting functions
#'
#' @param table_header A `table_header` object
#' @param ... The name of the arg is a column name, and the value is a function
#'
#' @return A `table_header` object
#' @keywords internal
#' @noRd
#' @examples
#' table_header_fmt_fun(
#'   table_header,
#'   p.value = style_pvalue,
#'   estimate = style_sigfig
#' )
table_header_fmt_fun <- function(table_header, ...) {
  # saving passed_dots arguments as a named list
  passed_dots <- list(...)

  # ordering the names to be the same as in table_header
  names_ordered <- table_header$column %>% intersect(names(passed_dots))
  passed_dots <- passed_dots[names_ordered]

  table_header_update <-
    tibble::tibble(
      column = table_header$column %>% intersect(names(passed_dots)),
      fmt_fun = passed_dots
    )

  # updating table_header
  table_header[
    table_header$column %in% table_header_update$column, # selecting rows
    c("column", "fmt_fun") # selecting columns
  ] <- table_header_update[c("column", "fmt_fun")]

  table_header
}


# table_header_fill_missing -----------------------------------------------------
#' Function fills out table_header when there are missing columns
#'
#' @param table_header A table_header object
#'
#' @return A table_header object
#' @keywords internal
#' @noRd
table_header_fill_missing <- function(table_header, table_body = NULL) {
  # if table_body is not null,
  # ensuring table_header has a row for each col in table_body
  if (!is.null(table_body)) {
    table_header <-
      tibble::tibble(column = names(table_body)) %>%
      dplyr::left_join(table_header, by = "column")
  }

  # table_header must be a tibble with the following columns with
  # at minimum a column named 'column'

  # label ----------------------------------------------------------------------
  if (!"label" %in% names(table_header)) {
    table_header$label <- table_header$column
  }

  # hide -----------------------------------------------------------------------
  # lgl vector
  if (!"hide" %in% names(table_header)) {
    table_header$hide <- TRUE
  }

  # align ----------------------------------------------------------------------
  if (!"align" %in% names(table_header)) {
    table_header$align <-
      ifelse(table_header$column %in% c("label", "groupname_col"), "left", "center")
  }

  # missing_emdash -------------------------------------------------------------
  # results in logical vector indicating which missing cells to replace with emdash
  if (!"missing_emdash" %in% names(table_header)) {
    table_header$missing_emdash <- NA_character_
  }

  # indent ---------------------------------------------------------------------
  # results in logical vector indicating which cells to indent in table_body
  if (!"indent" %in% names(table_header)) {
    table_header$indent <- ifelse(table_header$column == "label",
      "row_type != 'label'", NA_character_
    )
  }

  # text_interpret -------------------------------------------------------------
  # currently defaults to `gt::md` as the only option
  if (!"text_interpret" %in% names(table_header)) {
    table_header$text_interpret <- "gt::md"
  }

  # bold -----------------------------------------------------------------------
  # results in logical vector indicating which cells to bold
  if (!"bold" %in% names(table_header)) {
    table_header$bold <- NA_character_
  }

  # italic ---------------------------------------------------------------------
  # results in logical vector indicating which cells to bold
  if (!"italic" %in% names(table_header)) {
    table_header$italic <- NA_character_
  }

  # fmt_fun --------------------------------------------------------------------
  # list of functions that format the column
  if (!"fmt_fun" %in% names(table_header)) {
    table_header$fmt_fun <- list(NULL)
  }

  # footnote_abbrev ------------------------------------------------------------
  if (!"footnote_abbrev" %in% names(table_header)) {
    table_header$footnote_abbrev <- NA_character_
  }

  # footnote -------------------------------------------------------------------
  if (!"footnote" %in% names(table_header)) {
    table_header$footnote <- NA_character_
  }

  # spanning_header ------------------------------------------------------------
  if (!"spanning_header" %in% names(table_header)) {
    table_header$spanning_header <- NA_character_
  }

  # filling in missing values with default -------------------------------------
  table_header <-
    table_header %>%
    dplyr::mutate(
      label = dplyr::coalesce(.data$label, .data$column),
      hide = dplyr::coalesce(.data$hide, TRUE),
      text_interpret = dplyr::coalesce(.data$text_interpret, "gt::md"),
      align = dplyr::coalesce(.data$align, "center")
    )

  table_header
}
