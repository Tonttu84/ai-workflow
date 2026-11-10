# Data and ML projects

Rules for projects that fit models to data. A project's `AGENTS.md` pulls this file in ("Data and ML rules: `templates/data-science.md` in the ai-workflow clone") and states its own splits, metric and baseline. The shared rules still apply: tests first, the gate, decisions in `docs/decisions.md`.

## 1. Leakage is tested, not judged

Information from the test set or the future must not reach training. Each rule below comes with a test. The tests call the project's own code, never a scikit-learn object built inside the test: a test that builds its own splitter tests scikit-learn, not the project. The sketches use pytest, pandas, scikit-learn and hypothesis; `load_raw`, `split_by_time`, `train_model` (the training entry point, raw data in, fitted pipeline out), `make_cv`, `make_features` and `encode_target` stand for the project's functions, and `CUTOFF`, `HORIZON` (in time steps), `STEP` (one time step, such as `pd.Timedelta(days=1)`), `FEATURES` and `TARGET` for its constants.

- **Preprocessing that learns from data** (scaling, imputation, encoding, feature selection) is a step in a `sklearn.pipeline.Pipeline`, fitted on the training split only. Looking inside the fitted scaler misses scaling done upstream, before the split, so the test changes the test rows and asserts training did not notice:

  ```python
  def test_training_never_sees_test_rows():
      raw = load_raw()
      _, test = split_by_time(raw, CUTOFF)
      changed = raw.copy()
      changed.loc[test.index, FEATURES] *= 100.0
      changed.loc[test.index, TARGET] += 1_000.0
      probe = raw.loc[test.index, FEATURES]
      np.testing.assert_allclose(
          train_model(raw).predict(probe), train_model(changed).predict(probe)
      )
  ```

- **Time series predicting the future are split by time, never randomly.** Model selection uses expanding-window validation (`sklearn.model_selection.TimeSeriesSplit`) or rolling-origin (its `max_train_size`):

  ```python
  def test_every_test_row_is_after_every_train_row():
      train, test = split_by_time(load_raw(), CUTOFF)
      assert train["ts"].max() < test["ts"].min()

  def test_cv_folds_respect_time():
      ts = load_raw()["ts"]
      for tr, te in make_cv(ts):  # test rows come HORIZON steps after training
          assert ts.iloc[te].min() - ts.iloc[tr].max() > HORIZON * STEP
  ```

  `TimeSeriesSplit` counts rows: its `gap` and `max_train_size` are rows, not time steps. With several rows per time step (a panel, such as many cities a day), a gap of 7 rows is less than 7 days, and a fold boundary can put one day on both sides; the test above catches both. Split the sorted time steps instead, so that `gap` counts time steps:

  ```python
  def make_cv(ts, n_splits=5, gap=HORIZON):
      steps = np.sort(ts.unique())
      for tr, te in TimeSeriesSplit(n_splits=n_splits, gap=gap).split(steps):
          yield np.flatnonzero(ts.isin(steps[tr])), np.flatnonzero(ts.isin(steps[te]))
  ```

- **Lagged and rolling features use only the past**: shift before rolling (`y.shift(1).rolling(7).mean()`). A property test changes the future and asserts the past features stay put. Row `cut` is compared too: its features must not see its own target.

  ```python
  @given(cut=st.integers(min_value=10, max_value=90))
  def test_features_ignore_the_future(cut):
      df = synthetic_series(n=100, seed=0)
      changed = df.copy()
      changed.loc[changed.index[cut:], "y"] += 1_000.0
      pd.testing.assert_frame_equal(
          make_features(df).iloc[: cut + 1], make_features(changed).iloc[: cut + 1]
      )
  ```

- **Anything computed from the target** (target encoding, target-based feature selection) is computed out of fold. `sklearn.preprocessing.TargetEncoder.fit_transform` cross-fits; `fit(X, y).transform(X)` on the same rows does not. Give it fixed folds through `cv`: newer scikit-learn deprecates the encoder's own `shuffle` and `random_state`, and with unseeded folds two fits differ and the test fails for the wrong reason. (Its smoothing parameter is `smooth`.)

  ```python
  def encode_target(X, y):
      folds = KFold(n_splits=5, shuffle=True, random_state=0)
      return TargetEncoder(target_type="continuous", cv=folds).fit_transform(X, y)
  ```

  Test: a row's own target never moves its own encoding.

  ```python
  def test_target_encoding_is_out_of_fold():
      train, _ = split_by_time(load_raw(), CUTOFF)
      X, y = train[["city"]], train[TARGET].copy()
      before = encode_target(X, y)
      y.iloc[0] += 1_000.0
      assert encode_target(X, y)[0, 0] == pytest.approx(before[0, 0])
  ```

## 2. Baseline first

Before anything complex, fit the simplest sensible model: last value or seasonal naive for forecasts, the mean or `sklearn.dummy.DummyRegressor`, the majority class or a logistic regression for classification. Every later model is reported against it on the same metric, split and folds. Compare them fold by fold: take the difference from the baseline in each fold, then the mean of those differences and their spread. A model whose mean gain is not clearly larger than that spread has not beaten the baseline.

## 3. Valid metrics, stated up front

Choose the metric for the problem and write it in `docs/decisions.md` before comparing models.

- MAE is in the target's units and robust to outliers; RMSE punishes large errors; MAPE breaks near zero and punishes over-forecasts more than under-forecasts, so for series near zero prefer relative MAE (divided by the baseline's MAE on the same test rows) or MASE (scaled by the in-sample MAE of the naive forecast).
- With imbalanced classes, accuracy hides failure: use precision and recall at a stated threshold, average precision (`sklearn.metrics.average_precision_score`) or balanced accuracy.
- When probabilities are used as probabilities, check calibration: `sklearn.metrics.brier_score_loss` and `sklearn.calibration.calibration_curve`.
- Report uncertainty where it is cheap: the mean and spread over folds (`sklearn.model_selection.cross_validate`; for a time series pass the time folds as `cv`, such as `cv=list(make_cv(ts))` or a `TimeSeriesSplit`), or a bootstrap of the test-set metric. Neighbouring errors in a time series are correlated, so resample blocks of consecutive rows (a block bootstrap), not single rows.

## 4. A model report per model

Each model that is kept gets a short report (`reports/<model>.md` or the project's equivalent):

- **Why this model**: the alternatives tried and why they lost, as rows in the decision log.
- **Feature importance**: `sklearn.inspection.permutation_importance` on held-out data, not impurity-based importance (it is computed on training data and favours high-cardinality features). Correlated features cover for each other: permuting one leaves the other carrying the signal, so both can look unimportant. Permute a correlated group together, or cluster correlated features and keep one per cluster.
- **Residuals**: where and when the model is wrong, by time, by segment and against the predicted value.
- **Strengths and weaknesses**: the cases it handles well, the ones it does not, and what would fix them.

Prefer an interpretable model (linear, small tree, baseline plus corrections) unless a complex one shows a gain over it, measured fold by fold as for the baseline.

## 5. Exploration and features

Exploratory notebooks are fine. Anything that ships (loading, cleaning, features, training, evaluation) moves into tested modules in the package; notebooks import from it rather than holding the only copy.

Every engineered feature gets a one-line hypothesis before it is tried ("orders drop on public holidays"); common sense is enough. Record the result, kept or dropped and by how much the metric moved, in the model report or the decision log.

## 6. Reproducibility

- Fixed seeds: `random_state` on every estimator and splitter, `np.random.default_rng(seed)` for anything else.
- Data versions recorded: a version tag or a SHA-256 of each input file, written beside every result.
- The environment locked with uv (`uv.lock` committed).
- One command regenerates the result table from raw data, and that command is in `AGENTS.md`.

## 7. Software engineering

The shared rules already cover it: a package, not one notebook; a README with install and run instructions; the Python stack from the working agreements (uv, pytest, ruff, pyright strict in the gate and CI); function limits from `templates/function-limits.md`; data from outside validated where it enters (`templates/hardening-brief.md`).
