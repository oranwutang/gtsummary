# touchstone_clear()

refs <- c(Sys.getenv("GITHUB_BASE_REF", "benchmark2"))
# refs <- c(Sys.getenv("GITHUB_BASE_REF", "benchmark2"), Sys.getenv("GITHUB_HEAD_REF", "master"))
# refs <- c(Sys.getenv("GITHUB_BASE_REF", "touchstone"), Sys.getenv("GITHUB_HEAD_REF", "touchstone"))
timer <- purrr::partial(touchstone::benchmark_run_ref,
                        refs = refs, n = 10
)


# timer(
#   expr_before_benchmark = c("library(styler)", "cache_deactivate()"),
#   without_cache = 'style_pkg("touchstone/sources/here", filetype = c("R", "rmd"))'
# )

timer(
  expr_before_benchmark=c("library(gtsummary)", "library(magrittr)"),
  simple_BM = "tbl_summary(trial)",
)


timer(
  expr_before_benchmark=c("library(gtsummary)", "library(magrittr)"),
  complex_BM = "tbl_summary(trial, by = trt) %>% add_overall() %>% add_p() %>% add_q(quiet = TRUE) %>% add_n()",
)

for (benchmark in touchstone::benchmark_ls()) {
  timings <- touchstone::benchmark_read(benchmark, refs)

  library(ggplot2)
  library(magrittr)
  timings %>%
    ggplot(aes(x = elapsed, color = ref)) +
    geom_density()
  fs::path("touchstone/plots/", benchmark) %>%
    fs::path_ext_set("png") %>%
    ggsave()

  tbl <- timings %>%
    dplyr::group_by(.data$ref) %>%
    dplyr::summarise(m = mean(.data$elapsed)) %>%
    tibble::deframe()

  diff_percent <- round(100 * (tbl[refs[2]] - tbl[refs[1]]) / tbl[refs[1]], 1)
  cat(
    glue::glue("{benchmark}: {round(tbl[refs[1]], 2)} -> {round(tbl[refs[2]], 2)} ({diff_percent}%)"),
    fill = TRUE,
    file = "touchstone/pr-comment/info.txt",
    append = TRUE
  )
}
