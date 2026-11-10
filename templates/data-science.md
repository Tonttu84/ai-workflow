# Data and ML projects

Rules for projects that fit models to data. A project's `AGENTS.md` pulls this file in ("Data and ML rules: `templates/data-science.md` in the ai-workflow clone") and states its own splits, metric and baseline. The shared rules still apply: tests first, the gate, decisions in `docs/decisions.md`.

## 1. Leakage is tested, not judged

Information from the test set or the future must not reach training. Each rule below comes with a test; the sketches use pytest, pandas and scikit-learn, and the names `make_features`, `split_by_time` and `build_pipeline` stand for the project's own functions.

- **Preprocessing that learns from data** (scaling, imputation, encoding, feature selection) is a step in a `sklearn.pipeline.Pipeline`, fitted on the training split only. Assert it never saw a test row:

  ```python
  def test_scaler_fitted_on_train_only(df):
      train, test = split_by_time(df, cutoff="2024-01-01")
      pipe = build_pipeline().fit(train[FEATURES], train[TARGET])
      scaler = pipe.named_steps["scale"]
      assert scaler.n_samples_seen_ == len(train)
      np.testing.assert_allclose(scaler.mean_, train[FEATURES].mean())
  ```

- **Time series predicting the future are split by time, never randomly.** Model selection uses expanding-window validation (`sklearn.model_selection.TimeSeriesSplit`; `max_train_size` makes it rolling, `gap` leaves out the rows a forecast horizon would not yet have):

  ```python
  def test_every_test_row_is_after_every_train_row(df):
      train, test = split_by_time(df, cutoff="2024-01-01")
      assert train["ts"].max() < test["ts"].min()

  def test_cv_folds_respect_time(df):
      df = df.sort_values("ts")
      for tr, te in TimeSeriesSplit(n_splits=5, gap=HORIZON).split(df):
          assert df["ts"].iloc[tr].max() < df["ts"].iloc[te].min()
  ```

- **Lagged and rolling features use only the past**: shift before rolling (`y.shift(1).rolling(7).mean()`). A property test changes the future and asserts the past features stay put:

  ```python
  @given(cut=st.integers(min_value=10, max_value=90))
  def test_features_ignore_the_future(cut):
      df = synthetic_series(n=100, seed=0)
      changed = df.copy()
      changed.loc[changed.index[cut:], "y"] += 1_000.0
      pd.testing.assert_frame_equal(
          make_features(df).iloc[:cut], make_features(changed).iloc[:cut]
      )
  ```

- **Anything computed from the target** (target encoding, target-based feature selection) is computed out of fold. `sklearn.preprocessing.TargetEncoder.fit_transform` cross-fits; `fit(X, y).transform(X)` on the same rows does not, so use `fit_transform` on training data. Test: a row's own target never moves its own encoding:

  ```python
  def test_target_encoding_is_out_of_fold(train):
      enc = TargetEncoder(target_type="continuous", cv=5, random_state=0)
      before = enc.fit_transform(train[["city"]], train["y"])
      y = train["y"].copy()
      y.iloc[0] += 1_000.0
      after = enc.fit_transform(train[["city"]], y)
      assert after[0, 0] == pytest.approx(before[0, 0])
  ```

## 2. Baseline first

Before anything complex, fit the simplest sensible model: last value or seasonal naive for forecasts, the mean or `sklearn.dummy.DummyRegressor`, the majority class or a logistic regression for classification. Every later model is reported against it on the same metric, split and folds. A model that does not beat the baseline by more than the fold spread has not beaten it.

## 3. Valid metrics, stated up front

Choose the metric for the problem and write it in `docs/decisions.md` before comparing models.

- MAE is in the target's units and robust to outliers; RMSE punishes large errors; MAPE breaks near zero and punishes over-forecasts more than under-forecasts, so prefer MAE scaled by the baseline's MAE (MASE-style) for series near zero.
- With imbalanced classes, accuracy hides failure: use precision and recall at a stated threshold, average precision (`sklearn.metrics.average_precision_score`) or balanced accuracy.
- When probabilities are used as probabilities, check calibration: `sklearn.metrics.brier_score_loss` and `sklearn.calibration.calibration_curve`.
- Report uncertainty where it is cheap: the mean and spread over folds (`cross_validate`), or a bootstrap of the test-set metric.

## 4. A model report per model

Each model that is kept gets a short report (`reports/<model>.md` or the project's equivalent):

- **Why this model**: the alternatives tried and why they lost, as rows in the decision log.
- **Feature importance**: `sklearn.inspection.permutation_importance` on held-out data, not impurity-based importance (it is computed on training data and favours high-cardinality features). Correlated features share importance; say so when it matters.
- **Residuals**: where and when the model is wrong, by time, by segment and against the predicted value.
- **Strengths and weaknesses**: the cases it handles well, the ones it does not, and what would fix them.

Prefer an interpretable model (linear, small tree, baseline plus corrections) unless a complex one shows a gain larger than the fold spread.

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
