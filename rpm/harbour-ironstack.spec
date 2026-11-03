Name:       harbour-ironstack
Summary:    IronStack training log client
Version:    0.3.0
Release:    1
License:    AGPLv3
URL:        https://github.com/JonneSaloranta/ironstack
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   qt5-qtdeclarative-import-multimedia
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  desktop-file-utils

%description
Native Sailfish OS client for a self-hosted IronStack instance: training
with programs, workouts and personal records, body tracking, activities,
stretching and nutrition, like the web.

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5 VERSION=%{version}
%make_build

%install
%qmake5_install

desktop-file-install --delete-original \
  --dir %{buildroot}%{_datadir}/applications \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Tue Nov 03 2026 Jonne Saloranta <saloranta.jonne@gmail.com> - 0.3.0-1
- Cover: today's calories and protein against the target, and a quick
  entry action, when no workout is on.

* Tue Nov 03 2026 Jonne Saloranta <saloranta.jonne@gmail.com> - 0.2.0-1
- Progress page: training summary, body changes, strength trend, weekly
  and muscle group volume, personal records.
- Nutrition statistics, "Is your current target working?" and observed
  maintenance; Open Food Facts search by name or barcode.
- Body tracking reminder; stretching timer sounds (Audio permission).
- Body tracking, activities, stretching and nutrition like the web.
- Fixes: diary meals and days, built-in and deleted recipes in the diary,
  new items opening their page, shopping list ticks kept.

* Fri Oct 23 2026 Jonne Saloranta <saloranta.jonne@gmail.com> - 0.1.0-1
- First version: programs, workouts, set logging, history and records.
