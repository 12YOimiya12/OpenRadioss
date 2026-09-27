#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

#if defined(MYREAL4)
typedef float my_real;
#else
typedef double my_real;
#endif

#if defined(_MSC_VER)
#define THREAD_LOCAL __declspec(thread)
#elif defined(__GNUC__) || defined(__clang__)
#define THREAD_LOCAL __thread
#else
#define THREAD_LOCAL
#endif

#define UNUSED(x) (void)(x)
#define USERLIB_VERSION 1300000000
#define KF_NPARAM 25
#define KF_NUVAR 8

enum {
    KF_E = 0,
    KF_NU,
    KF_FC,
    KF_A,
    KF_N,
    KF_B,
    KF_M,
    KF_T,
    KF_D1,
    KF_D2,
    KF_BETA,
    KF_EPSDOT0,
    KF_RATES,
    KF_RATET,
    KF_ALPHA0,
    KF_PCRUSH,
    KF_PLOCK,
    KF_KE,
    KF_K1,
    KF_K2,
    KF_K3,
    KF_GAMMA,
    KF_PSAT,
    KF_SIGLIM,
    KF_EPSF_MIN
};

typedef struct {
    double v[KF_NPARAM];
} kf_params;

static THREAD_LOCAL my_real *g_so[6];
static THREAD_LOCAL my_real *g_de[6];
static THREAD_LOCAL my_real *g_rho0;
static THREAD_LOCAL my_real *g_rot[9];

static THREAD_LOCAL my_real *g_shell_so[5];
static THREAD_LOCAL my_real *g_shell_thkn;

static THREAD_LOCAL my_real *solid_s[6];
static THREAD_LOCAL my_real *solid_sv[6];
static THREAD_LOCAL my_real *solid_dpla;
static THREAD_LOCAL int solid_capacity;
static THREAD_LOCAL int solid_n;

static THREAD_LOCAL my_real *shell_s[5];
static THREAD_LOCAL my_real *shell_sv[5];
static THREAD_LOCAL my_real *shell_dpla;
static THREAD_LOCAL my_real *shell_etse;
static THREAD_LOCAL my_real *shell_thkn;
static THREAD_LOCAL int shell_capacity;
static THREAD_LOCAL int shell_n;

static double clamp_double(double x, double lo, double hi)
{
    if (x < lo) {
        return lo;
    }
    if (x > hi) {
        return hi;
    }
    return x;
}

static int grow_array(my_real **array, int n)
{
    my_real *tmp = (my_real *)realloc(*array, (size_t)n * sizeof(my_real));

    if (!tmp) {
        return 0;
    }

    *array = tmp;
    return 1;
}

static int ensure_solid_capacity(int n)
{
    int i;

    if (n <= solid_capacity) {
        return 1;
    }

    for (i = 0; i < 6; ++i) {
        if (!grow_array(&solid_s[i], n) || !grow_array(&solid_sv[i], n)) {
            return 0;
        }
    }
    if (!grow_array(&solid_dpla, n)) {
        return 0;
    }

    solid_capacity = n;
    return 1;
}

static int ensure_shell_capacity(int n)
{
    int i;

    if (n <= shell_capacity) {
        return 1;
    }

    for (i = 0; i < 5; ++i) {
        if (!grow_array(&shell_s[i], n) || !grow_array(&shell_sv[i], n)) {
            return 0;
        }
    }
    if (!grow_array(&shell_dpla, n) || !grow_array(&shell_etse, n) || !grow_array(&shell_thkn, n)) {
        return 0;
    }

    shell_capacity = n;
    return 1;
}

static void copy_fortran_string(char *dst, size_t dst_size, const char *src, int len)
{
    int i;
    int n;

    if (!dst || dst_size == 0) {
        return;
    }

    dst[0] = '\0';
    if (!src || len <= 0) {
        return;
    }

    n = len;
    if ((size_t)n >= dst_size) {
        n = (int)dst_size - 1;
    }

    for (i = 0; i < n; ++i) {
        dst[i] = src[i];
    }
    dst[n] = '\0';

    while (n > 0 && isspace((unsigned char)dst[n - 1])) {
        dst[n - 1] = '\0';
        --n;
    }
}

static void set_default_kf(kf_params *p)
{
    double *v = p->v;

    v[KF_E] = 3.10e10;
    v[KF_NU] = 0.20;
    v[KF_FC] = 1.00e8;
    v[KF_A] = 1.60;
    v[KF_N] = 0.75;
    v[KF_B] = 0.20;
    v[KF_M] = 0.60;
    v[KF_T] = 1.00e7;
    v[KF_D1] = 0.04;
    v[KF_D2] = 0.85;
    v[KF_BETA] = 0.20;
    v[KF_EPSDOT0] = 1.0e-6;
    v[KF_RATES] = 0.02;
    v[KF_RATET] = 0.02;
    v[KF_ALPHA0] = 1.05;
    v[KF_PCRUSH] = 1.0e7;
    v[KF_PLOCK] = 4.0e8;
    v[KF_KE] = 1.722222222e10;
    v[KF_K1] = 1.722222222e10;
    v[KF_K2] = 0.0;
    v[KF_K3] = 0.0;
    v[KF_GAMMA] = 0.0;
    v[KF_PSAT] = 5.0e8;
    v[KF_SIGLIM] = 8.0e8;
    v[KF_EPSF_MIN] = 1.0e-4;
}

static void sanitize_kf(kf_params *p)
{
    double *v = p->v;
    double K;

    if (v[KF_E] <= 0.0) {
        v[KF_E] = 3.10e10;
    }
    if (v[KF_NU] <= -0.999 || v[KF_NU] >= 0.499) {
        v[KF_NU] = 0.20;
    }
    if (v[KF_FC] <= 0.0) {
        v[KF_FC] = 1.0e8;
    }
    if (v[KF_A] <= 0.0) {
        v[KF_A] = 1.0;
    }
    if (v[KF_N] < 0.0) {
        v[KF_N] = 0.0;
    }
    if (v[KF_B] < 0.0) {
        v[KF_B] = 0.0;
    }
    if (v[KF_M] < 0.0) {
        v[KF_M] = 0.0;
    }
    if (v[KF_T] < 0.0) {
        v[KF_T] = 0.0;
    }
    if (v[KF_D1] <= 0.0) {
        v[KF_D1] = 0.04;
    }
    if (v[KF_EPSDOT0] <= 0.0) {
        v[KF_EPSDOT0] = 1.0e-6;
    }
    if (v[KF_ALPHA0] < 1.0) {
        v[KF_ALPHA0] = 1.0;
    }
    K = v[KF_E] / (3.0 * (1.0 - 2.0 * v[KF_NU]));
    if (v[KF_KE] <= 0.0) {
        v[KF_KE] = K;
    }
    if (v[KF_K1] <= 0.0) {
        v[KF_K1] = K;
    }
    if (v[KF_PCRUSH] < 0.0) {
        v[KF_PCRUSH] = 0.0;
    }
    if (v[KF_PLOCK] <= v[KF_PCRUSH]) {
        v[KF_PLOCK] = v[KF_PCRUSH] + 10.0 * v[KF_FC];
    }
    if (v[KF_PSAT] <= 0.0) {
        v[KF_PSAT] = v[KF_PLOCK];
    }
    if (v[KF_SIGLIM] <= 0.0) {
        v[KF_SIGLIM] = 10.0 * v[KF_FC];
    }
    if (v[KF_EPSF_MIN] <= 0.0) {
        v[KF_EPSF_MIN] = 1.0e-8;
    }
}

static int parse_kf_parameters(const char *root, int ilaw, kf_params *p)
{
    char filename[1024];
    char line[1024];
    double values[KF_NPARAM];
    int count = 0;
    FILE *fp;

    snprintf(filename, sizeof(filename), "SI%s_%04d.scr", root ? root : "", ilaw);
    fp = fopen(filename, "r");
    if (!fp) {
        return 0;
    }

    while (fgets(line, sizeof(line), fp)) {
        char *cursor = line;

        while (*cursor && isspace((unsigned char)*cursor)) {
            ++cursor;
        }
        if (*cursor == '\0' || *cursor == '#' || *cursor == '/' || *cursor == '$') {
            continue;
        }

        while (*cursor && count < KF_NPARAM) {
            char *end = cursor;
            double value;

            while (*cursor && isspace((unsigned char)*cursor)) {
                ++cursor;
            }
            if (*cursor == '\0' || *cursor == '#' || *cursor == '$') {
                break;
            }
            value = strtod(cursor, &end);
            if (end == cursor) {
                break;
            }
            values[count++] = value;
            cursor = end;
        }
    }

    fclose(fp);

    if (count < KF_NPARAM) {
        return 0;
    }

    memcpy(p->v, values, sizeof(values));
    sanitize_kf(p);
    return 1;
}

static void write_starter_echo(const char *root, int ilaw, const kf_params *p, int used_defaults)
{
    char filename[1024];
    FILE *fp;
    const double *v = p->v;

    snprintf(filename, sizeof(filename), "SO%s_%04d.scr", root ? root : "", ilaw);
    fp = fopen(filename, "w");
    if (!fp) {
        return;
    }

    fprintf(fp, "\n");
    fprintf(fp, "    USER MATERIAL LAW99.%02d: Kong-Fang rock/concrete MVP\n", ilaw == 99 ? 2 : ilaw);
    fprintf(fp, "    Interface     = /MAT/USER02 via LAW99 dynamic user library\n");
    fprintf(fp, "    Sign          = compression pressure P is positive; OpenRadioss tensile stress remains positive\n");
    fprintf(fp, "    Parameter set = %s\n", used_defaults ? "built-in defaults" : "input card");
    fprintf(fp, "    E             = %.12g\n", v[KF_E]);
    fprintf(fp, "    nu            = %.12g\n", v[KF_NU]);
    fprintf(fp, "    fc            = %.12g\n", v[KF_FC]);
    fprintf(fp, "    A, N          = %.12g %.12g\n", v[KF_A], v[KF_N]);
    fprintf(fp, "    B, M          = %.12g %.12g\n", v[KF_B], v[KF_M]);
    fprintf(fp, "    T             = %.12g\n", v[KF_T]);
    fprintf(fp, "    D1, D2, beta  = %.12g %.12g %.12g\n", v[KF_D1], v[KF_D2], v[KF_BETA]);
    fprintf(fp, "    epsdot0,S,T   = %.12g %.12g %.12g\n", v[KF_EPSDOT0], v[KF_RATES], v[KF_RATET]);
    fprintf(fp, "    alpha0        = %.12g\n", v[KF_ALPHA0]);
    fprintf(fp, "    Pcrush, Plock = %.12g %.12g\n", v[KF_PCRUSH], v[KF_PLOCK]);
    fprintf(fp, "    Ke,K1,K2,K3   = %.12g %.12g %.12g %.12g\n", v[KF_KE], v[KF_K1], v[KF_K2], v[KF_K3]);
    fprintf(fp, "    Gamma         = %.12g\n", v[KF_GAMMA]);
    fprintf(fp, "    Psat,Siglim   = %.12g %.12g\n", v[KF_PSAT], v[KF_SIGLIM]);
    fprintf(fp, "    epsf_min      = %.12g\n", v[KF_EPSF_MIN]);
    fprintf(fp, "    UVAR(1)       = damage D\n");
    fprintf(fp, "    UVAR(2)       = porosity alpha\n");
    fprintf(fp, "    UVAR(3)       = equivalent plastic strain\n");
    fprintf(fp, "    UVAR(4)       = compression-positive pressure\n");
    fprintf(fp, "    UVAR(5)       = current shear yield stress\n");
    fprintf(fp, "    UVAR(6)       = equivalent strain rate\n");
    fprintf(fp, "    UVAR(7)       = relative volume J = rho0/rho\n");
    fprintf(fp, "    UVAR(8)       = mu = rho/rho0 - 1\n");
    fclose(fp);
}

static void fill_starter_material(const kf_params *p,
                                  my_real *uparam, int maxuparam, int *nuparam,
                                  int *nuvar, int *ifunc, int maxfunc, int *nfunc,
                                  my_real *parmat)
{
    const double *v = p->v;
    double K = v[KF_E] / (3.0 * (1.0 - 2.0 * v[KF_NU]));
    int i;

    if (nuparam) {
        *nuparam = KF_NPARAM;
    }
    if (nuvar) {
        *nuvar = KF_NUVAR;
    }
    if (nfunc) {
        *nfunc = 0;
    }
    if (ifunc && maxfunc > 0) {
        for (i = 0; i < maxfunc; ++i) {
            ifunc[i] = 0;
        }
    }
    if (uparam && maxuparam > 0) {
        int n = maxuparam < KF_NPARAM ? maxuparam : KF_NPARAM;
        for (i = 0; i < n; ++i) {
            uparam[i] = (my_real)v[i];
        }
    }
    if (parmat) {
        for (i = 0; i < 100; ++i) {
            parmat[i] = (my_real)0;
        }
        parmat[0] = (my_real)K;
        parmat[1] = (my_real)v[KF_E];
        parmat[2] = (my_real)v[KF_NU];
        parmat[15] = (my_real)0;
        parmat[16] = (my_real)0;
    }
}

static double uvar_get(my_real *uvar, int n, int nuvar, int ivar, int i, double fallback)
{
    if (!uvar || n <= 0 || ivar <= 0 || nuvar < ivar) {
        return fallback;
    }
    return (double)uvar[(ivar - 1) * n + i];
}

static void uvar_set(my_real *uvar, int n, int nuvar, int ivar, int i, double value)
{
    if (!uvar || n <= 0 || ivar <= 0 || nuvar < ivar) {
        return;
    }
    uvar[(ivar - 1) * n + i] = (my_real)value;
}

static int is_valid_rotation(const double r[9])
{
    double c1 = r[0] * r[0] + r[3] * r[3] + r[6] * r[6];
    double c2 = r[1] * r[1] + r[4] * r[4] + r[7] * r[7];
    double c3 = r[2] * r[2] + r[5] * r[5] + r[8] * r[8];
    double d12 = r[0] * r[1] + r[3] * r[4] + r[6] * r[7];
    double d13 = r[0] * r[2] + r[3] * r[5] + r[6] * r[8];
    double d23 = r[1] * r[2] + r[4] * r[5] + r[7] * r[8];

    return fabs(c1 - 1.0) < 1.0e-6 &&
           fabs(c2 - 1.0) < 1.0e-6 &&
           fabs(c3 - 1.0) < 1.0e-6 &&
           fabs(d12) < 1.0e-6 &&
           fabs(d13) < 1.0e-6 &&
           fabs(d23) < 1.0e-6;
}

static void voigt_to_tensor(const double v[6], double t[3][3])
{
    t[0][0] = v[0];
    t[1][1] = v[1];
    t[2][2] = v[2];
    t[0][1] = v[3];
    t[1][0] = v[3];
    t[1][2] = v[4];
    t[2][1] = v[4];
    t[0][2] = v[5];
    t[2][0] = v[5];
}

static void tensor_to_voigt(const double t[3][3], double v[6])
{
    v[0] = t[0][0];
    v[1] = t[1][1];
    v[2] = t[2][2];
    v[3] = 0.5 * (t[0][1] + t[1][0]);
    v[4] = 0.5 * (t[1][2] + t[2][1]);
    v[5] = 0.5 * (t[0][2] + t[2][0]);
}

static void rotate_voigt(const double in[6], const double r[9], int to_local, double out[6])
{
    double a[3][3];
    double b[3][3];
    int i;
    int j;
    int k;
    int l;

    voigt_to_tensor(in, a);
    for (i = 0; i < 3; ++i) {
        for (j = 0; j < 3; ++j) {
            b[i][j] = 0.0;
            for (k = 0; k < 3; ++k) {
                for (l = 0; l < 3; ++l) {
                    if (to_local) {
                        b[i][j] += r[k * 3 + i] * a[k][l] * r[l * 3 + j];
                    } else {
                        b[i][j] += r[i * 3 + k] * a[k][l] * r[j * 3 + l];
                    }
                }
            }
        }
    }
    tensor_to_voigt(b, out);
}

static void strain_voigt_to_tensor(const double v[6], double t[3][3])
{
    t[0][0] = v[0];
    t[1][1] = v[1];
    t[2][2] = v[2];
    t[0][1] = 0.5 * v[3];
    t[1][0] = 0.5 * v[3];
    t[1][2] = 0.5 * v[4];
    t[2][1] = 0.5 * v[4];
    t[0][2] = 0.5 * v[5];
    t[2][0] = 0.5 * v[5];
}

static void tensor_to_strain_voigt(const double t[3][3], double v[6])
{
    v[0] = t[0][0];
    v[1] = t[1][1];
    v[2] = t[2][2];
    v[3] = t[0][1] + t[1][0];
    v[4] = t[1][2] + t[2][1];
    v[5] = t[0][2] + t[2][0];
}

static void rotate_strain_voigt(const double in[6], const double r[9], int to_local, double out[6])
{
    double a[3][3];
    double b[3][3];
    int i;
    int j;
    int k;
    int l;

    strain_voigt_to_tensor(in, a);
    for (i = 0; i < 3; ++i) {
        for (j = 0; j < 3; ++j) {
            b[i][j] = 0.0;
            for (k = 0; k < 3; ++k) {
                for (l = 0; l < 3; ++l) {
                    if (to_local) {
                        b[i][j] += r[k * 3 + i] * a[k][l] * r[l * 3 + j];
                    } else {
                        b[i][j] += r[i * 3 + k] * a[k][l] * r[j * 3 + l];
                    }
                }
            }
        }
    }
    tensor_to_strain_voigt(b, out);
}

static void set_identity_rotation(double r[9])
{
    int k;

    for (k = 0; k < 9; ++k) {
        r[k] = 0.0;
    }
    r[0] = 1.0;
    r[4] = 1.0;
    r[8] = 1.0;
}

static void point_rotation(int i, double r[9])
{
    int k;

    set_identity_rotation(r);
    for (k = 0; k < 9; ++k) {
        if (!g_rot[k]) {
            return;
        }
    }
    for (k = 0; k < 9; ++k) {
        r[k] = (double)g_rot[k][i];
    }
    if (!is_valid_rotation(r)) {
        set_identity_rotation(r);
    }
}

static double kf_poly_pressure(const kf_params *p, double mu_matrix, double e_int)
{
    const double *v = p->v;

    return v[KF_K1] * mu_matrix +
           v[KF_K2] * mu_matrix * mu_matrix +
           v[KF_K3] * mu_matrix * mu_matrix * mu_matrix +
           v[KF_GAMMA] * e_int;
}

static double kf_pressure_update(const kf_params *p, double mu_total, double alpha_old,
                                 double e_int, double *alpha_new)
{
    const double *v = p->v;
    const double tol = 1.0e-8;
    const int max_iter = 40;
    double alpha = alpha_old;
    double p_elastic;
    double mu_matrix;
    double pressure;
    int iter;

    if (alpha < 1.0 || alpha > v[KF_ALPHA0]) {
        alpha = v[KF_ALPHA0];
    }

    p_elastic = v[KF_KE] * mu_total;
    if (p_elastic <= v[KF_PCRUSH]) {
        *alpha_new = alpha;
        return p_elastic;
    }

    if (alpha <= 1.0 || p_elastic >= v[KF_PLOCK]) {
        *alpha_new = 1.0;
        return kf_poly_pressure(p, mu_total, e_int);
    }

    for (iter = 0; iter < max_iter; ++iter) {
        double ratio;
        double residual;
        double dp_dmu;
        double dp_dalpha;
        double df_dalpha;
        double denom = v[KF_PLOCK] - v[KF_PCRUSH];
        double step;

        mu_matrix = alpha * (1.0 + mu_total) - 1.0;
        pressure = kf_poly_pressure(p, mu_matrix, e_int);

        if (pressure >= v[KF_PLOCK]) {
            alpha = 1.0;
            break;
        }
        if (denom <= 0.0) {
            break;
        }

        ratio = (v[KF_PLOCK] - pressure) / denom;
        residual = alpha - 1.0 - (v[KF_ALPHA0] - 1.0) * ratio * ratio;
        if (fabs(residual) < tol) {
            break;
        }

        dp_dmu = v[KF_K1] + 2.0 * v[KF_K2] * mu_matrix + 3.0 * v[KF_K3] * mu_matrix * mu_matrix;
        dp_dalpha = dp_dmu * (1.0 + mu_total);
        df_dalpha = 1.0 + 2.0 * (v[KF_ALPHA0] - 1.0) * ratio * dp_dalpha / denom;
        if (fabs(df_dalpha) < 1.0e-20) {
            break;
        }

        step = residual / df_dalpha;
        alpha -= step;
        alpha = clamp_double(alpha, 1.0, alpha_old);
    }

    *alpha_new = alpha;
    mu_matrix = alpha * (1.0 + mu_total) - 1.0;
    pressure = kf_poly_pressure(p, mu_matrix, e_int);
    if (pressure >= v[KF_PLOCK]) {
        *alpha_new = 1.0;
        pressure = kf_poly_pressure(p, mu_total, e_int);
    }
    return pressure;
}

static double kf_bulk_modulus(const kf_params *p, double mu_total, double alpha,
                              double pressure)
{
    const double *v = p->v;
    double p_elastic = v[KF_KE] * mu_total;
    double mu_matrix;
    double dp_dmu;
    double bulk;

    if (p_elastic <= v[KF_PCRUSH]) {
        return v[KF_KE];
    }

    if (alpha < 1.0 || alpha > v[KF_ALPHA0]) {
        alpha = 1.0;
    }
    if (alpha <= 1.0 || p_elastic >= v[KF_PLOCK] || pressure >= v[KF_PLOCK]) {
        mu_matrix = mu_total;
        alpha = 1.0;
    } else {
        mu_matrix = alpha * (1.0 + mu_total) - 1.0;
    }

    dp_dmu = v[KF_K1] + 2.0 * v[KF_K2] * mu_matrix +
             3.0 * v[KF_K3] * mu_matrix * mu_matrix;
    bulk = (1.0 + mu_total) * alpha * dp_dmu;
    if (bulk < v[KF_KE]) {
        bulk = v[KF_KE];
    }
    return bulk;
}

static double kf_rate_factor(const kf_params *p, double pressure, double strain_rate)
{
    const double *v = p->v;
    double r = strain_rate / v[KF_EPSDOT0];
    double dff;

    if (r < 1.0) {
        r = 1.0;
    }

    if (pressure >= 0.0) {
        dff = 1.0 + pow(r, v[KF_RATES]);
    } else {
        dff = pow(r, v[KF_RATET]);
    }
    if (dff < 1.0) {
        dff = 1.0;
    }
    return dff;
}

static double kf_strength(const kf_params *p, double pressure, double damage, double dff)
{
    const double *v = p->v;
    double p_cap = pressure;
    double max_arg;
    double res_arg;
    double sigma_max;
    double sigma_res;
    double sigma_y;

    if (p_cap > v[KF_PSAT]) {
        p_cap = v[KF_PSAT];
    }

    max_arg = (p_cap + v[KF_T]) / v[KF_FC];
    if (max_arg < 0.0) {
        max_arg = 0.0;
    }
    sigma_max = v[KF_FC] * v[KF_A] * pow(max_arg, v[KF_N]) * dff;
    if (sigma_max > v[KF_SIGLIM]) {
        sigma_max = v[KF_SIGLIM];
    }

    res_arg = pressure / v[KF_FC];
    if (res_arg < 0.0) {
        res_arg = 0.0;
    }
    sigma_res = v[KF_FC] * v[KF_B] * pow(res_arg, v[KF_M]);

    damage = clamp_double(damage, 0.0, 1.0);
    sigma_y = damage * sigma_res + (1.0 - damage) * sigma_max;
    if (pressure < 0.0 && v[KF_T] > 0.0 && sigma_y > v[KF_T] * dff) {
        sigma_y = v[KF_T] * dff;
    }
    if (sigma_y < 0.0) {
        sigma_y = 0.0;
    }
    return sigma_y;
}

static double kf_failure_strain(const kf_params *p, double pressure)
{
    const double *v = p->v;
    double arg = (pressure + v[KF_T]) / v[KF_FC];
    double epsf;

    if (arg < 1.0e-12) {
        arg = 1.0e-12;
    }
    epsf = v[KF_D1] * pow(arg, v[KF_D2]);
    if (epsf < v[KF_EPSF_MIN]) {
        epsf = v[KF_EPSF_MIN];
    }
    return epsf;
}

EXPORT void userlib_id(int *info)
{
    if (info) {
        *info = USERLIB_VERSION;
    }
}

EXPORT void set_callback(void *callback_array[200])
{
    UNUSED(callback_array);
}

EXPORT void st_lecm99_(int *ilaw, char *rootn, int *rootlen, int *iuser_law,
                       my_real *uparam, int *maxuparam, int *nuparam, int *nuvar,
                       int *ifunc, int *maxfunc, int *nfunc, my_real *parmat)
{
    char root[512];
    kf_params p;
    int law = ilaw ? *ilaw : 99;
    int maxu = maxuparam ? *maxuparam : 0;
    int maxf = maxfunc ? *maxfunc : 0;
    int used_defaults;

    UNUSED(iuser_law);
    set_default_kf(&p);
    copy_fortran_string(root, sizeof(root), rootn, rootlen ? *rootlen : 0);
    used_defaults = !parse_kf_parameters(root, law, &p);
    if (used_defaults) {
        fprintf(stderr, "raduser_kf_law99: using default KF parameters; scratch file was not readable or incomplete\n");
    }

    write_starter_echo(root, law, &p, used_defaults);
    fill_starter_material(&p, uparam, maxu, nuparam, nuvar, ifunc, maxf, nfunc, parmat);
}

EXPORT void ST_LECM99(int *ilaw, char *rootn, int *rootlen, int *iuser_law,
                      my_real *uparam, int *maxuparam, int *nuparam, int *nuvar,
                      int *ifunc, int *maxfunc, int *nfunc, my_real *parmat)
{
    st_lecm99_(ilaw, rootn, rootlen, iuser_law, uparam, maxuparam, nuparam, nuvar,
               ifunc, maxfunc, nfunc, parmat);
}

EXPORT void st_get_userbuf_var_(int *id, char *title)
{
    UNUSED(title);
    if (id) {
        *id = 0;
    }
}

EXPORT void ST_GET_USERBUF_VAR(int *id, char *title)
{
    st_get_userbuf_var_(id, title);
}

EXPORT void eng_get_law_user_var_(int *NCYCLE, int *IMAT, int *IPTR, int *IPTS, int *IPTT,
                                  my_real *R11, my_real *R12, my_real *R13,
                                  my_real *R21, my_real *R22, my_real *R23,
                                  my_real *R31, my_real *R32, my_real *R33,
                                  my_real *SO1, my_real *SO2, my_real *SO3,
                                  my_real *SO4, my_real *SO5, my_real *SO6,
                                  my_real *EP1, my_real *EP2, my_real *EP3,
                                  my_real *EP4, my_real *EP5, my_real *EP6,
                                  my_real *ES1, my_real *ES2, my_real *ES3,
                                  my_real *ES4, my_real *ES5, my_real *ES6,
                                  my_real *DE1, my_real *DE2, my_real *DE3,
                                  my_real *DE4, my_real *DE5, my_real *DE6,
                                  my_real *RHO0,
                                  my_real *S1, my_real *S2, my_real *S3,
                                  my_real *S4, my_real *S5, my_real *S6,
                                  my_real *SV1, my_real *SV2, my_real *SV3,
                                  my_real *SV4, my_real *SV5, my_real *SV6)
{
    UNUSED(NCYCLE);
    UNUSED(IMAT);
    UNUSED(IPTR);
    UNUSED(IPTS);
    UNUSED(IPTT);
    UNUSED(EP1);
    UNUSED(EP2);
    UNUSED(EP3);
    UNUSED(EP4);
    UNUSED(EP5);
    UNUSED(EP6);
    UNUSED(ES1);
    UNUSED(ES2);
    UNUSED(ES3);
    UNUSED(ES4);
    UNUSED(ES5);
    UNUSED(ES6);
    UNUSED(S1);
    UNUSED(S2);
    UNUSED(S3);
    UNUSED(S4);
    UNUSED(S5);
    UNUSED(S6);
    UNUSED(SV1);
    UNUSED(SV2);
    UNUSED(SV3);
    UNUSED(SV4);
    UNUSED(SV5);
    UNUSED(SV6);

    g_so[0] = SO1;
    g_so[1] = SO2;
    g_so[2] = SO3;
    g_so[3] = SO4;
    g_so[4] = SO5;
    g_so[5] = SO6;

    g_de[0] = DE1;
    g_de[1] = DE2;
    g_de[2] = DE3;
    g_de[3] = DE4;
    g_de[4] = DE5;
    g_de[5] = DE6;

    g_rho0 = RHO0;

    g_rot[0] = R11;
    g_rot[1] = R12;
    g_rot[2] = R13;
    g_rot[3] = R21;
    g_rot[4] = R22;
    g_rot[5] = R23;
    g_rot[6] = R31;
    g_rot[7] = R32;
    g_rot[8] = R33;
}

EXPORT void ENG_GET_LAW_USER_VAR(int *NCYCLE, int *IMAT, int *IPTR, int *IPTS, int *IPTT,
                                 my_real *R11, my_real *R12, my_real *R13,
                                 my_real *R21, my_real *R22, my_real *R23,
                                 my_real *R31, my_real *R32, my_real *R33,
                                 my_real *SO1, my_real *SO2, my_real *SO3,
                                 my_real *SO4, my_real *SO5, my_real *SO6,
                                 my_real *EP1, my_real *EP2, my_real *EP3,
                                 my_real *EP4, my_real *EP5, my_real *EP6,
                                 my_real *ES1, my_real *ES2, my_real *ES3,
                                 my_real *ES4, my_real *ES5, my_real *ES6,
                                 my_real *DE1, my_real *DE2, my_real *DE3,
                                 my_real *DE4, my_real *DE5, my_real *DE6,
                                 my_real *RHO0,
                                 my_real *S1, my_real *S2, my_real *S3,
                                 my_real *S4, my_real *S5, my_real *S6,
                                 my_real *SV1, my_real *SV2, my_real *SV3,
                                 my_real *SV4, my_real *SV5, my_real *SV6)
{
    eng_get_law_user_var_(NCYCLE, IMAT, IPTR, IPTS, IPTT,
                          R11, R12, R13, R21, R22, R23, R31, R32, R33,
                          SO1, SO2, SO3, SO4, SO5, SO6,
                          EP1, EP2, EP3, EP4, EP5, EP6,
                          ES1, ES2, ES3, ES4, ES5, ES6,
                          DE1, DE2, DE3, DE4, DE5, DE6, RHO0,
                          S1, S2, S3, S4, S5, S6, SV1, SV2, SV3, SV4, SV5, SV6);
}

EXPORT void eng_sigeps99_(int *NEL, int *NUPARAM, int *NUVAR, int *ILAW_USER, int *NFUNC,
                          int *IFUNC, int *NPF, my_real *TF, my_real *TIME, my_real *TIMESTEP,
                          my_real *UPARAM, my_real *RHO, my_real *VOLUME, my_real *EINT,
                          int *NGL, my_real *SOUNDSP, my_real *VISCMAX, my_real *UVAR,
                          my_real *OFF, my_real *SIGY, my_real *PLA)
{
    int n = NEL && *NEL > 0 ? *NEL : 0;
    int nuvar = NUVAR ? *NUVAR : 0;
    int i;
    kf_params p;
    double E;
    double nu;
    double G;
    double K;
    const double tiny = 1.0e-20;

    UNUSED(NUPARAM);
    UNUSED(ILAW_USER);
    UNUSED(NFUNC);
    UNUSED(IFUNC);
    UNUSED(NPF);
    UNUSED(TF);
    UNUSED(TIME);
    UNUSED(NGL);

    solid_n = 0;
    if (n <= 0 || !ensure_solid_capacity(n)) {
        return;
    }
    solid_n = n;

    set_default_kf(&p);
    if (UPARAM) {
        int k;
        for (k = 0; k < KF_NPARAM; ++k) {
            p.v[k] = (double)UPARAM[k];
        }
        sanitize_kf(&p);
    }

    E = p.v[KF_E];
    nu = p.v[KF_NU];
    G = E / (2.0 * (1.0 + nu));
    K = E / (3.0 * (1.0 - 2.0 * nu));

    for (i = 0; i < n; ++i) {
        double old_sig_global[6];
        double deps_global[6];
        double old_sig[6];
        double deps[6];
        double dev_trial[6];
        double sig_new_local[6];
        double sig_new_global[6];
        double rot[9];
        double mean_old;
        double p_old;
        double trace_deps;
        double mu_total;
        double J;
        double alpha_old;
        double alpha_new;
        double pressure;
        double e_int = EINT ? (double)EINT[i] : 0.0;
        double bulk_eff;
        double seq_trial;
        double damage_old;
        double damage_new;
        double epbar_old;
        double epbar_new;
        double epsdot_eq;
        double dff;
        double sigma_y;
        double dgamma = 0.0;
        double scale = 1.0;
        double tensile_vol;
        double epsf;
        double dt = TIMESTEP && *TIMESTEP > (my_real)0 ? (double)*TIMESTEP : 1.0;
        double work;
        int k;

        for (k = 0; k < 6; ++k) {
            old_sig_global[k] = g_so[k] ? (double)g_so[k][i] : 0.0;
            deps_global[k] = g_de[k] ? (double)g_de[k][i] : 0.0;
            solid_sv[k][i] = (my_real)0;
        }
        point_rotation(i, rot);
        rotate_voigt(old_sig_global, rot, 1, old_sig);
        rotate_strain_voigt(deps_global, rot, 1, deps);

        if (OFF && OFF[i] <= (my_real)0) {
            for (k = 0; k < 6; ++k) {
                solid_s[k][i] = (my_real)old_sig_global[k];
            }
            solid_dpla[i] = (my_real)0;
            continue;
        }

        damage_old = clamp_double(uvar_get(UVAR, n, nuvar, 1, i, 0.0), 0.0, 1.0);
        alpha_old = uvar_get(UVAR, n, nuvar, 2, i, p.v[KF_ALPHA0]);
        if (alpha_old < 1.0 || alpha_old > p.v[KF_ALPHA0]) {
            alpha_old = p.v[KF_ALPHA0];
        }
        epbar_old = uvar_get(UVAR, n, nuvar, 3, i, 0.0);
        if (epbar_old < 0.0) {
            epbar_old = 0.0;
        }

        mean_old = (old_sig[0] + old_sig[1] + old_sig[2]) / 3.0;
        p_old = -mean_old;
        trace_deps = deps[0] + deps[1] + deps[2];

        if (RHO && g_rho0 && RHO[i] > (my_real)0 && g_rho0[i] > (my_real)0) {
            J = (double)g_rho0[i] / (double)RHO[i];
            mu_total = 1.0 / J - 1.0;
        } else if (VOLUME && VOLUME[i] > (my_real)1.0e-20) {
            J = (double)VOLUME[i];
            mu_total = 1.0 / J - 1.0;
        } else {
            mu_total = p_old / p.v[KF_KE] - trace_deps;
            J = 1.0 / fmax(1.0 + mu_total, 1.0e-12);
        }

        pressure = kf_pressure_update(&p, mu_total, alpha_old, e_int, &alpha_new);
        bulk_eff = kf_bulk_modulus(&p, mu_total, alpha_new, pressure);
        if (bulk_eff < K) {
            bulk_eff = K;
        }

        dev_trial[0] = old_sig[0] - mean_old + 2.0 * G * (deps[0] - trace_deps / 3.0);
        dev_trial[1] = old_sig[1] - mean_old + 2.0 * G * (deps[1] - trace_deps / 3.0);
        dev_trial[2] = old_sig[2] - mean_old + 2.0 * G * (deps[2] - trace_deps / 3.0);
        dev_trial[3] = old_sig[3] + G * deps[3];
        dev_trial[4] = old_sig[4] + G * deps[4];
        dev_trial[5] = old_sig[5] + G * deps[5];

        seq_trial = sqrt(1.5 * (dev_trial[0] * dev_trial[0] +
                                dev_trial[1] * dev_trial[1] +
                                dev_trial[2] * dev_trial[2] +
                                2.0 * (dev_trial[3] * dev_trial[3] +
                                       dev_trial[4] * dev_trial[4] +
                                       dev_trial[5] * dev_trial[5])));
        epsdot_eq = sqrt(2.0 / 3.0 *
                         ((deps[0] - trace_deps / 3.0) * (deps[0] - trace_deps / 3.0) +
                          (deps[1] - trace_deps / 3.0) * (deps[1] - trace_deps / 3.0) +
                          (deps[2] - trace_deps / 3.0) * (deps[2] - trace_deps / 3.0) +
                          0.5 * (deps[3] * deps[3] + deps[4] * deps[4] + deps[5] * deps[5]))) /
                    dt;

        dff = kf_rate_factor(&p, pressure, epsdot_eq);
        sigma_y = kf_strength(&p, pressure, damage_old, dff);

        if (seq_trial > tiny && seq_trial > sigma_y) {
            dgamma = (seq_trial - sigma_y) / (3.0 * G);
            if (dgamma < 0.0) {
                dgamma = 0.0;
            }
            scale = sigma_y / seq_trial;
            scale = clamp_double(scale, 0.0, 1.0);
        }

        tensile_vol = trace_deps > 0.0 && pressure < 0.0 ? trace_deps : 0.0;
        epsf = kf_failure_strain(&p, pressure);
        damage_new = damage_old + (dgamma + p.v[KF_BETA] * tensile_vol) / epsf;
        damage_new = clamp_double(damage_new, damage_old, 1.0);
        epbar_new = epbar_old + dgamma;

        sig_new_local[0] = -pressure + scale * dev_trial[0];
        sig_new_local[1] = -pressure + scale * dev_trial[1];
        sig_new_local[2] = -pressure + scale * dev_trial[2];
        sig_new_local[3] = scale * dev_trial[3];
        sig_new_local[4] = scale * dev_trial[4];
        sig_new_local[5] = scale * dev_trial[5];
        rotate_voigt(sig_new_local, rot, 0, sig_new_global);

        for (k = 0; k < 6; ++k) {
            solid_s[k][i] = (my_real)sig_new_global[k];
        }
        solid_dpla[i] = (my_real)dgamma;

        uvar_set(UVAR, n, nuvar, 1, i, damage_new);
        uvar_set(UVAR, n, nuvar, 2, i, alpha_new);
        uvar_set(UVAR, n, nuvar, 3, i, epbar_new);
        uvar_set(UVAR, n, nuvar, 4, i, pressure);
        uvar_set(UVAR, n, nuvar, 5, i, sigma_y);
        uvar_set(UVAR, n, nuvar, 6, i, epsdot_eq);
        uvar_set(UVAR, n, nuvar, 7, i, J);
        uvar_set(UVAR, n, nuvar, 8, i, mu_total);

        if (PLA) {
            PLA[i] = (my_real)epbar_new;
        }
        if (SIGY) {
            SIGY[i] = (my_real)sigma_y;
        }
        if (SOUNDSP && RHO && RHO[i] > (my_real)0) {
            SOUNDSP[i] = (my_real)sqrt((bulk_eff + 4.0 * G / 3.0) / (double)RHO[i]);
        }
        if (VISCMAX) {
            VISCMAX[i] = (my_real)0;
        }
        if (EINT && RHO && RHO[i] > (my_real)0) {
            work = 0.5 * ((old_sig_global[0] + sig_new_global[0]) * deps_global[0] +
                          (old_sig_global[1] + sig_new_global[1]) * deps_global[1] +
                          (old_sig_global[2] + sig_new_global[2]) * deps_global[2] +
                          (old_sig_global[3] + sig_new_global[3]) * deps_global[3] +
                          (old_sig_global[4] + sig_new_global[4]) * deps_global[4] +
                          (old_sig_global[5] + sig_new_global[5]) * deps_global[5]);
            EINT[i] = (my_real)((double)EINT[i] + work / (double)RHO[i]);
        }
    }
}

EXPORT void ENG_SIGEPS99(int *NEL, int *NUPARAM, int *NUVAR, int *ILAW_USER, int *NFUNC,
                         int *IFUNC, int *NPF, my_real *TF, my_real *TIME, my_real *TIMESTEP,
                         my_real *UPARAM, my_real *RHO, my_real *VOLUME, my_real *EINT,
                         int *NGL, my_real *SOUNDSP, my_real *VISCMAX, my_real *UVAR,
                         my_real *OFF, my_real *SIGY, my_real *PLA)
{
    eng_sigeps99_(NEL, NUPARAM, NUVAR, ILAW_USER, NFUNC, IFUNC, NPF, TF, TIME, TIMESTEP,
                  UPARAM, RHO, VOLUME, EINT, NGL, SOUNDSP, VISCMAX, UVAR, OFF, SIGY, PLA);
}

EXPORT void eng_set_law_user_var_(my_real *S1, my_real *S2, my_real *S3,
                                  my_real *S4, my_real *S5, my_real *S6,
                                  my_real *SV1, my_real *SV2, my_real *SV3,
                                  my_real *SV4, my_real *SV5, my_real *SV6,
                                  my_real *DPLA)
{
    my_real *S[6];
    my_real *SV[6];
    int i;
    int k;

    S[0] = S1;
    S[1] = S2;
    S[2] = S3;
    S[3] = S4;
    S[4] = S5;
    S[5] = S6;
    SV[0] = SV1;
    SV[1] = SV2;
    SV[2] = SV3;
    SV[3] = SV4;
    SV[4] = SV5;
    SV[5] = SV6;

    for (i = 0; i < solid_n; ++i) {
        for (k = 0; k < 6; ++k) {
            if (S[k]) {
                S[k][i] = solid_s[k][i];
            }
            if (SV[k]) {
                SV[k][i] = solid_sv[k][i];
            }
        }
        if (DPLA) {
            DPLA[i] = solid_dpla[i];
        }
    }
}

EXPORT void ENG_SET_LAW_USER_VAR(my_real *S1, my_real *S2, my_real *S3,
                                 my_real *S4, my_real *S5, my_real *S6,
                                 my_real *SV1, my_real *SV2, my_real *SV3,
                                 my_real *SV4, my_real *SV5, my_real *SV6,
                                 my_real *DPLA)
{
    eng_set_law_user_var_(S1, S2, S3, S4, S5, S6, SV1, SV2, SV3, SV4, SV5, SV6, DPLA);
}

EXPORT void eng_get_lawc_user_var_(int *NCYCLE, int *IMAT, int *ILAYER, int *NPTA, int *IFLAG,
                                   my_real *R11, my_real *R12, my_real *R13,
                                   my_real *R21, my_real *R22, my_real *R23,
                                   my_real *R31, my_real *R32, my_real *R33,
                                   my_real *SIGOXX, my_real *SIGOYY, my_real *SIGOXY,
                                   my_real *SIGOYZ, my_real *SIGOZX,
                                   my_real *EPSPXX, my_real *EPSPYY, my_real *EPSPXY,
                                   my_real *EPSPYZ, my_real *EPSPZX,
                                   my_real *EPSXX, my_real *EPSYY, my_real *EPSXY,
                                   my_real *EPSYZ, my_real *EPSZX,
                                   my_real *DEPSXX, my_real *DEPSYY, my_real *DEPSXY,
                                   my_real *DEPSYZ, my_real *DEPSZX,
                                   my_real *THKLYL, my_real *THKN,
                                   my_real *SIGNXX, my_real *SIGNYY, my_real *SIGNXY,
                                   my_real *SIGNYZ, my_real *SIGNZX,
                                   my_real *SIGVXX, my_real *SIGVYY, my_real *SIGVXY,
                                   my_real *SIGVYZ, my_real *SIGVZX, my_real *DPLA)
{
    UNUSED(NCYCLE);
    UNUSED(IMAT);
    UNUSED(ILAYER);
    UNUSED(NPTA);
    UNUSED(IFLAG);
    UNUSED(R11);
    UNUSED(R12);
    UNUSED(R13);
    UNUSED(R21);
    UNUSED(R22);
    UNUSED(R23);
    UNUSED(R31);
    UNUSED(R32);
    UNUSED(R33);
    UNUSED(EPSPXX);
    UNUSED(EPSPYY);
    UNUSED(EPSPXY);
    UNUSED(EPSPYZ);
    UNUSED(EPSPZX);
    UNUSED(EPSXX);
    UNUSED(EPSYY);
    UNUSED(EPSXY);
    UNUSED(EPSYZ);
    UNUSED(EPSZX);
    UNUSED(DEPSXX);
    UNUSED(DEPSYY);
    UNUSED(DEPSXY);
    UNUSED(DEPSYZ);
    UNUSED(DEPSZX);
    UNUSED(THKLYL);
    UNUSED(SIGNXX);
    UNUSED(SIGNYY);
    UNUSED(SIGNXY);
    UNUSED(SIGNYZ);
    UNUSED(SIGNZX);
    UNUSED(SIGVXX);
    UNUSED(SIGVYY);
    UNUSED(SIGVXY);
    UNUSED(SIGVYZ);
    UNUSED(SIGVZX);
    UNUSED(DPLA);

    g_shell_so[0] = SIGOXX;
    g_shell_so[1] = SIGOYY;
    g_shell_so[2] = SIGOXY;
    g_shell_so[3] = SIGOYZ;
    g_shell_so[4] = SIGOZX;
    g_shell_thkn = THKN;
}

EXPORT void ENG_GET_LAWC_USER_VAR(int *NCYCLE, int *IMAT, int *ILAYER, int *NPTA, int *IFLAG,
                                  my_real *R11, my_real *R12, my_real *R13,
                                  my_real *R21, my_real *R22, my_real *R23,
                                  my_real *R31, my_real *R32, my_real *R33,
                                  my_real *SIGOXX, my_real *SIGOYY, my_real *SIGOXY,
                                  my_real *SIGOYZ, my_real *SIGOZX,
                                  my_real *EPSPXX, my_real *EPSPYY, my_real *EPSPXY,
                                  my_real *EPSPYZ, my_real *EPSPZX,
                                  my_real *EPSXX, my_real *EPSYY, my_real *EPSXY,
                                  my_real *EPSYZ, my_real *EPSZX,
                                  my_real *DEPSXX, my_real *DEPSYY, my_real *DEPSXY,
                                  my_real *DEPSYZ, my_real *DEPSZX,
                                  my_real *THKLYL, my_real *THKN,
                                  my_real *SIGNXX, my_real *SIGNYY, my_real *SIGNXY,
                                  my_real *SIGNYZ, my_real *SIGNZX,
                                  my_real *SIGVXX, my_real *SIGVYY, my_real *SIGVXY,
                                  my_real *SIGVYZ, my_real *SIGVZX, my_real *DPLA)
{
    eng_get_lawc_user_var_(NCYCLE, IMAT, ILAYER, NPTA, IFLAG,
                           R11, R12, R13, R21, R22, R23, R31, R32, R33,
                           SIGOXX, SIGOYY, SIGOXY, SIGOYZ, SIGOZX,
                           EPSPXX, EPSPYY, EPSPXY, EPSPYZ, EPSPZX,
                           EPSXX, EPSYY, EPSXY, EPSYZ, EPSZX,
                           DEPSXX, DEPSYY, DEPSXY, DEPSYZ, DEPSZX,
                           THKLYL, THKN, SIGNXX, SIGNYY, SIGNXY, SIGNYZ, SIGNZX,
                           SIGVXX, SIGVYY, SIGVXY, SIGVYZ, SIGVZX, DPLA);
}

EXPORT void eng_sigeps99c_(int *NEL, int *NUPARAM, int *NUVAR, int *ILAW_USER, int *NFUNC,
                           int *IFUNC, int *NPF, int *NGL, my_real *TF, my_real *TIME,
                           my_real *TIMESTEP, my_real *UPARAM, my_real *RHO, my_real *AREA,
                           my_real *EINT, my_real *SHF, my_real *SOUNDSP, my_real *VISCMAX,
                           my_real *PLA, my_real *UVAR, my_real *OFF, my_real *SIGY)
{
    int n = NEL && *NEL > 0 ? *NEL : 0;
    int i;
    int k;

    UNUSED(NUPARAM);
    UNUSED(NUVAR);
    UNUSED(ILAW_USER);
    UNUSED(NFUNC);
    UNUSED(IFUNC);
    UNUSED(NPF);
    UNUSED(NGL);
    UNUSED(TF);
    UNUSED(TIME);
    UNUSED(TIMESTEP);
    UNUSED(UPARAM);
    UNUSED(RHO);
    UNUSED(AREA);
    UNUSED(EINT);
    UNUSED(SHF);
    UNUSED(SOUNDSP);
    UNUSED(VISCMAX);
    UNUSED(PLA);
    UNUSED(UVAR);
    UNUSED(OFF);
    UNUSED(SIGY);

    shell_n = 0;
    if (n <= 0 || !ensure_shell_capacity(n)) {
        return;
    }
    shell_n = n;

    for (i = 0; i < n; ++i) {
        for (k = 0; k < 5; ++k) {
            shell_s[k][i] = g_shell_so[k] ? g_shell_so[k][i] : (my_real)0;
            shell_sv[k][i] = (my_real)0;
        }
        shell_dpla[i] = (my_real)0;
        shell_etse[i] = (my_real)0;
        shell_thkn[i] = g_shell_thkn ? g_shell_thkn[i] : (my_real)0;
    }
}

EXPORT void ENG_SIGEPS99C(int *NEL, int *NUPARAM, int *NUVAR, int *ILAW_USER, int *NFUNC,
                          int *IFUNC, int *NPF, int *NGL, my_real *TF, my_real *TIME,
                          my_real *TIMESTEP, my_real *UPARAM, my_real *RHO, my_real *AREA,
                          my_real *EINT, my_real *SHF, my_real *SOUNDSP, my_real *VISCMAX,
                          my_real *PLA, my_real *UVAR, my_real *OFF, my_real *SIGY)
{
    eng_sigeps99c_(NEL, NUPARAM, NUVAR, ILAW_USER, NFUNC, IFUNC, NPF, NGL, TF, TIME,
                   TIMESTEP, UPARAM, RHO, AREA, EINT, SHF, SOUNDSP, VISCMAX, PLA, UVAR, OFF, SIGY);
}

EXPORT void eng_set_lawc_user_var_(my_real *SIGNXX, my_real *SIGNYY, my_real *SIGNXY,
                                   my_real *SIGNYZ, my_real *SIGNZX,
                                   my_real *SIGVXX, my_real *SIGVYY, my_real *SIGVXY,
                                   my_real *SIGVYZ, my_real *SIGVZX,
                                   my_real *DPLA, my_real *ETSE, my_real *THKN)
{
    my_real *S[5];
    my_real *SV[5];
    int i;
    int k;

    S[0] = SIGNXX;
    S[1] = SIGNYY;
    S[2] = SIGNXY;
    S[3] = SIGNYZ;
    S[4] = SIGNZX;
    SV[0] = SIGVXX;
    SV[1] = SIGVYY;
    SV[2] = SIGVXY;
    SV[3] = SIGVYZ;
    SV[4] = SIGVZX;

    for (i = 0; i < shell_n; ++i) {
        for (k = 0; k < 5; ++k) {
            if (S[k]) {
                S[k][i] = shell_s[k][i];
            }
            if (SV[k]) {
                SV[k][i] = shell_sv[k][i];
            }
        }
        if (DPLA) {
            DPLA[i] = shell_dpla[i];
        }
        if (ETSE) {
            ETSE[i] = shell_etse[i];
        }
        if (THKN) {
            THKN[i] = shell_thkn[i];
        }
    }
}

EXPORT void ENG_SET_LAWC_USER_VAR(my_real *SIGNXX, my_real *SIGNYY, my_real *SIGNXY,
                                  my_real *SIGNYZ, my_real *SIGNZX,
                                  my_real *SIGVXX, my_real *SIGVYY, my_real *SIGVXY,
                                  my_real *SIGVYZ, my_real *SIGVZX,
                                  my_real *DPLA, my_real *ETSE, my_real *THKN)
{
    eng_set_lawc_user_var_(SIGNXX, SIGNYY, SIGNXY, SIGNYZ, SIGNZX,
                           SIGVXX, SIGVYY, SIGVXY, SIGVYZ, SIGVZX, DPLA, ETSE, THKN);
}

EXPORT void st_lecg_(void) {}
EXPORT void st_lecguser_(void) {}
EXPORT void st_lecm_(void) {}
EXPORT void st_lecr_(void) {}
EXPORT void st_lecsen_(void) {}
EXPORT void st_riniuser_(void) {}
EXPORT void st_siniusr_(void) {}
EXPORT void st_userwis_(void) {}
EXPORT void st_userwis_ini_(void) {}

EXPORT void eng_ruser_(void) {}
EXPORT void eng_sigeps_(void) {}
EXPORT void eng_sigepsc_(void) {}
EXPORT void eng_flaw_(void) {}
EXPORT void eng_flawc_(void) {}
EXPORT void eng_suser_(void) {}
EXPORT void eng_userint_(void) {}
EXPORT void eng_get_uintbuf_var_(void) {}
EXPORT void eng_userwi_(void) {}
EXPORT void eng_user_sens_(void) {}

EXPORT void ST_LECG(void) {}
EXPORT void ST_LECGUSER(void) {}
EXPORT void ST_LECM(void) {}
EXPORT void ST_LECR(void) {}
EXPORT void ST_LECSEN(void) {}
EXPORT void ST_RINIUSER(void) {}
EXPORT void ST_SINIUSR(void) {}
EXPORT void ST_USERWIS(void) {}
EXPORT void ST_USERWIS_INI(void) {}

EXPORT void ENG_RUSER(void) {}
EXPORT void ENG_SIGEPS(void) {}
EXPORT void ENG_SIGEPSC(void) {}
EXPORT void ENG_FLAW(void) {}
EXPORT void ENG_FLAWC(void) {}
EXPORT void ENG_SUSER(void) {}
EXPORT void ENG_USERINT(void) {}
EXPORT void ENG_GET_UINTBUF_VAR(void) {}
EXPORT void ENG_USERWI(void) {}
EXPORT void ENG_USER_SENS(void) {}
