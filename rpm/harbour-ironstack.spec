Name:       harbour-ironstack
Summary:    IronStack training log client
# The version is the repo-root VERSION file's (docs/RELEASING.md).
Version:    %(cat %{_sourcedir}/../VERSION)
Release:    1
License:    AGPLv3
URL:        https://github.com/JonneSaloranta/ironstack-jolla-client
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
strip %{buildroot}%{_bindir}/%{name}

desktop-file-install --delete-original \
  --dir %{buildroot}%{_datadir}/applications \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
