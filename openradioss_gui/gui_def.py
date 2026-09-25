# Copyright (C) 2026 SISW Siemens Industry Software Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining 
# a copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
# IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
import os
import tkinter as tk
from tkinter import messagebox, simpledialog
from tkinter import font as tkfont
import platform
import webbrowser
from button_with_highlight import ButtonWithHighlight
from placeholder_entry import PlaceholderEntry

arch=platform.system()

if arch=='Windows':
    button_width=9
elif arch=='Linux':
    button_width=10

class window:
    def __init__(self, vd3penabled, vtkhdfenabled,mpi_path,sp_status,starter_status,vtk_status,csv_status,vtkhdf_status,d3plot_status,script_dir):

        self.root = tk.Tk()
        self.root.title('OpenRadioss')
        self.vd3penabled = vd3penabled
        self.vtkhdfenabled = vtkhdfenabled
        self.mpi_path = mpi_path

        # Chinese labels need a font with CJK coverage and a little more room.
        # Configure the named Tk fonts directly : the option database cannot take
        # a multi-word family name ("Microsoft YaHei UI 9" is parsed as family
        # "Microsoft" + size "YaHei" and raises TclError).
        if arch == 'Windows':
            for font_name in ('TkDefaultFont', 'TkTextFont', 'TkMenuFont', 'TkHeadingFont'):
                try:
                    tkfont.nametofont(font_name).configure(family='Microsoft YaHei UI', size=9)
                except tk.TclError:
                    pass

        if arch == 'Windows':
            self.root.geometry('780x105')
            self.root.minsize(780, 105)
        elif arch == 'Linux':
            self.root.geometry('900x105')
            self.root.minsize(900, 105)
        self.root.resizable(True, True)

        # Icons
        if arch == 'Windows':
             self.root.iconbitmap(script_dir+'icon'+os.sep+'ross.ico')
             self.icon_folder = tk.PhotoImage(file=script_dir+'icon'+os.sep+'or_folder.png')
        elif arch == 'Linux':
             icon_image = tk.PhotoImage(file=script_dir+'icon'+os.sep+'ross.png')
             self.root.iconphoto(True, icon_image)
             self.icon_folder = tk.PhotoImage(file=script_dir+'icon'+os.sep+'or_folder.png')

        # Dropdown Variables
        self.variables = {
            '单精度': tk.BooleanVar(value=sp_status),
            '仅运行前处理': tk.BooleanVar(value=starter_status),
            '动画转 vtk': tk.BooleanVar(value=vtk_status),
            '动画转 vtkhdf': tk.BooleanVar(value=vtkhdf_status),
            '动画转 d3plot': tk.BooleanVar(value=d3plot_status),
            '时程转 csv': tk.BooleanVar(value=csv_status),
        }

        self.variable_flags = {
            '单精度': 'single_status',
            '仅运行前处理': 'starter_status',
            '动画转 vtk': 'vtk_status',
            '动画转 vtkhdf': 'vtkhdf_status',
            '动画转 d3plot': 'd3plot_status',
            '时程转 csv': 'csv_status',
        }

        # Frame file
        self.frame_file = tk.Frame(self.root)
        self.frame_file.pack(fill=tk.X, pady=(10,0))

        # Frame thread / MPI
        self.frame_thread = tk.Frame(self.root)
        self.frame_thread.pack(side=tk.LEFT, padx=(30, 0))

        self.frame_checkboxes = tk.Frame(self.frame_thread)
        self.frame_checkboxes.pack(side=tk.TOP)

        # Frame for Dropdown
        self.frame_dropdown = tk.Frame(self.frame_checkboxes)
        self.frame_dropdown.pack(side=tk.RIGHT)

        # Dropdown Button
        self.dropdown_button = tk.Menubutton(self.frame_dropdown, text="运行选项", relief=tk.RAISED)
        self.dropdown_menu = tk.Menu(self.dropdown_button, tearoff=False)
        self.dropdown_button.config(menu=self.dropdown_menu)

        # Buttons Frame
        self.frame_control = tk.Frame(self.root)
        self.frame_control.pack(side=tk.RIGHT, padx=(0, 30))

        # Explicitly add all labels to the dropdown
        for label in self.variables:
            if label == '动画转 vtkhdf' and not vtkhdfenabled:
                continue  # Skip Anim - vtkhdf if vtkhdfenabled is False
            if label == '动画转 d3plot' and not vd3penabled:
                continue  # Skip Anim - d3plot if vd3penabled is False

            # Add the checkbox to the dropdown menu
            self.dropdown_menu.add_checkbutton(label=label, variable=self.variables[label])

        # Pack the dropdown button
        self.dropdown_button.pack(side=tk.LEFT, padx=5)

    def get_selected_options(self):
        # Return the current state of the dropdown variables
        return self.variables


    def menubar(self):
        self.menubar = tk.Menu(self.root)
        self.root.config(menu=self.menubar)
        #
        self.config_menu = tk.Menu(self.menubar, tearoff=False)
        self.menubar.add_cascade(label="配置", menu=self.config_menu)
        #
        self.about_menu = tk.Menu(self.menubar, tearoff=False)
        self.menubar.add_cascade(label="信息", menu=self.about_menu)
        #
        self.config_menu.add_command(label="MPI 路径", command=self._set_mpi_path_dialog)
        #
        self.about_menu.add_command(label="获取最新版 OpenRadioss（GitHub 链接）", command=self._latestv_dialog)
        self.about_menu.add_command(label="获取本 GUI 的文档与最新版本（GitHub 链接）", command=self._latestgui_dialog)
        self.about_menu.add_command(label="获取最新版 VortexRadioss d3plot Python 模块（GitHub 链接）", command=self._latestvrad_dialog)
        self.about_menu.add_command(label="获取最新版 Kitware animtovtkhdf Python 模块（GitLab 链接）", command=self._latestvtkh_dialog)
        self.about_menu.add_command(label="访问 OpenRadioss 官网", command=self._orweb_dialog)
        self.about_menu.add_command(label="关于本 GUI", command=self._about_dialog)


    def file(self,text,command,icon_folder):
        job_file_entry = PlaceholderEntry(self.frame_file, placeholder_text=text, entry_width=83)
        job_file_entry.pack(side=tk.LEFT, expand=True, fill='x', padx=(30, 0), ipady=2)
        job_file_button = ButtonWithHighlight(self.frame_file, image=icon_folder, command=command, width=20)
        job_file_button.pack(side=tk.RIGHT, padx=(5, 30))
        return job_file_entry

    def thread_mpi(self,text,width,px,py):
        entry = PlaceholderEntry(self.frame_checkboxes, placeholder_text=text, entry_width=width)
        entry.pack(side=tk.LEFT,padx=px,ipady=py)
        return entry
    
    def button(self, text, command, pad):
        button = ButtonWithHighlight(self.frame_control, text=text, command=command,width=button_width)        
        button.pack(side=tk.LEFT, padx=pad)

    def close(self):
           self.root.destroy()

    # Private methods for menu bar
    def _latestv_dialog(self):
          webbrowser.open("https://github.com/OpenRadioss/OpenRadioss/releases")
    def _latestgui_dialog(self):
          webbrowser.open("https://github.com/OpenRadioss/Tools/tree/main/openradioss_gui")
    def _latestvrad_dialog(self):
          webbrowser.open("https://github.com/Vortex-CAE/Vortex-Radioss")
    def _latestvtkh_dialog(self):
          webbrowser.open("https://gitlab.kitware.com/keu-public/openradioss-to-vtkhdf")
    def _orweb_dialog(self):
          webbrowser.open("https://openradioss.org")
    def _about_dialog(self):
          messagebox.showinfo("关于", "本任务提交 GUI 来自 OpenRadioss tools" )
    def _set_mpi_path_dialog(self):
        value = simpledialog.askstring("MPI 路径", "请输入 MPI 安装的根目录：                      ", initialvalue=self.mpi_path)
        if value is not None:
            self.mpi_path = value
